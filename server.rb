#!/usr/bin/env ruby
require 'rubygems'

require './feed.rb'
require './entry.rb'
require './database.rb'

require 'sinatra'
require "sinatra/multi_route"
require 'rack-superfeedr'
require 'json'
require 'sinatra/browserid'
require 'sinatra/hijacker'
require 'nokogiri'
require 'tilt/erb'
include ERB::Util
use Rack::Session::Pool, :expire_after => 2628000
set :static_cache_control, [:public, max_age: 31536000]
register Sinatra::Hijacker
use Rack::Protection, except: :path_traversal

websockets = []

helpers do
    include Rack::Utils
    alias_method :h, :escape_html

    # Escape json strings
    def jh(string)
        JSON.generate(string, quirks_mode: true)
    end
    
    def isAdmin?
        if authorized?
            return Database.new.getAdminMail == authorized_email
        end
        return false
    end

    def protected!
        unless isAdmin?
            throw(:halt, [401, "Not authorized\n"])
        end
    end

    def truncate(text, length, append)
        return text.gsub(/^(.{#{length},}?).*$/m,'\1' + append)
    end

    def secret_url
        gen_secret_url
    end

    def getOption(name)
        Database.new.getOption(name)
    end

    def apiAccess!(token = nil)
        ctoken = Database.new.getOption("ctoken")
        if ctoken
            if token                
                return token == ctoken[0..63]  # note: the token only fits 64 chars
            else
                return request.env["HTTP_AUTHORIZATION"] == "GoogleLogin auth=#{ctoken}"
            end
            return false
        else
            warn "no ctoken set"
            return false
        end
    end
end

def loadConfiguration()
    db = Database.new
    Rack::Superfeedr.host = db.getOption("host")
    Rack::Superfeedr.login = db.getOption("superfeedrName")
    Rack::Superfeedr.password = db.getOption("superfeedrPassword")
end

def gen_secret_url()
    begin
        return Digest::RMD160.new << Database.new.getOption("secret")
    rescue TypeError
        return ""
    end
end

configure do
    loadConfiguration()
    set :protection, :except => [:path_traversal]
end

before do
    settings.browserid_login_button = url("/browserid.png")
end

use Rack::Superfeedr do |superfeedr|
    superfeedr.on_notification do |feed_id, body, url, request|
        feed_id = feed_id.to_i
        Database.new.log(name: "notification", log: body.to_s) if ! settings.production?
        notification = JSON.parse(body)
        Feed.new(id: feed_id).setName(name: notification["title"]) if notification["title"] && ! notification["title"].empty?
        if notification["items"]
            websockets.each {|feedsockets| feedsockets.each {|feedsocket| feedsocket.send_data({:updated_feed => feed_id}.to_json)} if feedsockets }
            notification["items"].each do |item|
                content = item["content"] || item["summary"]
                content = item["content"].length > item["summary"].length ? item["content"] : item["summary"]  if item["content"] && item["summary"]
                entry = Entry.new(url: item["permalinkUrl"], title: item["title"], content: content, feed_id: feed_id).save!
                websockets[feed_id].each {|feedsocket| feedsocket.send_data({:new_entry => entry.id}.to_json) if feedsocket} if websockets[feed_id]
            end
        else
            if notification["status"]["code"] != 0 && (Time.now - Time.at(notification["status"]["lastParse"])) > 604800
                # this was not a ping && for more than a week superfeedr was unable to parse this, so we need to unsubscribe to reduce load
                puts "unsubscribing #{feed_id}"
                Rack::Superfeedr.unsubscribe url, feed_id do |n|
                    puts "success!"
                    Feed.new(id: feed_id).unsubscribed!
                end
            end
        end
    end
end

## bazqux flavored reader api ##

post '/accounts/ClientLogin' do
    if Argon2::Password.verify_password(params["Passwd"], Database.new.getOption("clientPassword"))
        ctoken = SecureRandom.urlsafe_base64(256)
        Database.new.setOption("ctoken", ctoken) 
        erb :readerAuth, :layout => false, :locals => {:ctoken => ctoken}
    else
        return "Error=BadAuthentication"
    end
end

get '/reader/ping' do
    if apiAccess!
        return "ok"
    else
        return "Unauthorized"
    end
end

get '/reader/api/0/token' do
    if apiAccess!
        return Database.new.getOption("ctoken")
    end
end

get '/reader/directory/search' do
    return "Search is not yet supported"
end

get '/reader/api/0/user-info' do
    if apiAccess!
        erb :readerUserInfo, :layout => false, :locals => {:user => Database.new.getAdminMail}
    end
end

get '/reader/api/0/preference/list' do
    if params["output"] == "json"
        return '{"prefs":[]}'
    else
        return '<object><list name="prefs"/></object>'
    end
    
end

get '/reader/api/0/friends/list' do
    if params["output"] == "json"
        return '{"friends":[]}'
    else
        return '<object><list name="friends"/></object>'
    end
end

get '/reader/api/0/preference/stream/list' do
    erb :readerStream, :layout => false, :locals => {:output => params["output"]}
end

get '/reader/api/0/preference/stream/set' do
    # TODO
    return ""
end

get '/reader/api/0/tag/list' do
    erb :readerTaglist, :layout => false, :locals => {:output => params["output"]}
end

get '/reader/api/0/subscription/list' do
    if apiAccess!
        erb :readerSubscriptionlist, :layout => false, :locals => {:output => params["output"], :feeds => Database.new.getFeeds(onlyUnread: false)}
    end
end

get '/reader/subscriptions/export' do
    if apiAccess!
        content_type 'text/x-opml'
        erb :export, :layout => false, :locals => {:feeds => Database.new.getFeeds(onlyUnread: false)}
    end
end

post '/reader/api/0/subscription/quickadd' do
    if apiAccess!
        Rack::Superfeedr.base_path = url("/superfeedr/feed/", false)
        feed = subscribe(url: params["quickadd"], name: params["quickadd"])
        erb :readerQuickadd, :layout => false, :locals => {:feed => feed}
    end
end

post '/reader/api/0/subscription/edit' do
    if apiAccess!
        if params["ac"] == "unsubscribe" && params["s"]
            id = params["s"].gsub("feed/", "")
            feed = Feed.new(id: id)
            Rack::Superfeedr.unsubscribe(feed.url, id)
            feed.unsubscribed!
        end
    end
end

get '/reader/api/0/unread-count' do
    if apiAccess!
        feeds = Database.new.getFeeds(onlyUnread: true)
        total = feeds.inject(0){|sum, feed| sum + feed.entries.size}
        erb :readerUnread, :layout => false, :locals => {:output => params["output"], :feeds => feeds, :total => total}
    end
end

get '/reader/api/0/stream/items/ids' do
    if apiAccess!
        db = Database.new
        params["s"] ||= params["xt"]
        case params["s"]
        when "user/-/state/com.google/reading-list"
            # TODO: add continuation
            erb :readerStreamIds, :layout => false, :locals => {:output => params["output"], :entries => db.getEntries()}
        when "user/-/state/com.google/reading-list"
            # TODO: add continuation
            erb :readerStreamIds, :layout => false, :locals => {:output => params["output"], :entries => db.getMarkedEntries(nil)}
        when "user/-/state/com.google/read"
            # TODO: add continuation
            erb :readerStreamIds, :layout => false, :locals => {:output => params["output"], :entries => db.getEntries(nil, nil, true)}
        when "user/-/state/com.google/broadcast", "user/-/state/com.google/created"
            if params["output"] == "json"
                return '{"itemRefs":[]}'
            else
                return '<object><list name="itemRefs"></list></object>'
            end
        when /feed\//
            # TODO: add continuation
            id = params["s"].gsub("feed/", "")
            erb :readerStreamIds, :layout => false, :locals => {:output => params["output"], :entries => Feed.new(id: id).entries()}
        end
    end
end

get '/reader/api/0/stream/items/contents' do
    if apiAccess!
        # TODO: Add atom output
        # we need to manually get the params here, because the syntax of having multiple i=…&i=… collides with how sinatra does things
        entries = parseItemIds(request: request) 
        feed = Feed.new(id: entries.first.feed_id) 
        erb :readerStreamContent, :layout => false, :locals => {:output => params["output"], :entries => entries, :feed => feed}
    end
end

get %r{/reader/api/0/stream/contents(.*)}, %r{/reader/atom(.*)} do |feedId|
    if apiAccess!
        params["output"] = "atom" if request.env['rack.request.script_name'] == "/reader/atom"
        params["s"] = feedId if feedId && feedId.include?('feed/')   # legacy greader mode for News+
        params["s"] = feedId if feedId && feedId.include?('user/')   # legacy greader mode for News+
        params["s"] = params["s"][1..-1] if params["s"].chr == "/" # snyc theoretical bazqux api format with regex for next+
        db = Database.new
        case params["s"]
        when "user/-/state/com.google/reading-list"
            # TODO: add continuation
            feed = Feed.new(id: "reading-list", url: "/reading-list", name: "Reading List")
            erb :readerStreamContent, :layout => false, :locals => {:output => params["output"], :entries => db.getEntries(), :feed => feed}
        when "user/-/state/com.google/starred"
            # TODO: add continuation
            feed = Feed.new(id: "marked", url: "/marked", name: "Marked")
            erb :readerStreamContent, :layout => false, :locals => {:output => params["output"], :entries => db.getMarkedEntries(nil), :feed => feed}
        when "user/-/state/com.google/read"
            # TODO: add continuation
            feed = Feed.new(id: "read", url: "/read", name: "Read")
            erb :readerStreamContent, :layout => false, :locals => {:output => params["output"], :entries => db.getEntries(nil, nil, true), :feed => feed}
        when "user/-/state/com.google/broadcast", "user/-/state/com.google/created"
            if params["output"] == "json"
                return '{"itemRefs":[]}'
            else
                return '<object><list name="itemRefs"></list></object>'
            end
        when /feed\//
            # TODO: add continuation
            id = params["s"].gsub("feed/", "")
            feed = Feed.new(id: id)
            erb :readerStreamContent, :layout => false, :locals => {:output => params["output"], :entries => feed.entries(), :feed => feed}
        end
    end
end

post '/reader/api/0/edit-tag' do
    puts params
    if apiAccess!(params["T"])
        entries = parseItemIds(request: request)
        case params["a"]
        when "user/-/state/com.google/read" then entries.each{|entry| entry.read? ? entry.unread! : entry.read! }; return "OK" # return something to try to prevent clients from thinking it failed (what is ht expected output?)
        when "user/-/state/com.google/starred" then entries.each{|entry| entry.marked? ? entry.unmark! : entry.mark! }; return "OK";
        end
        return ""
    end
end

def parseItemIds(request:)
    if request.request_method == "GET"
        raw = request.env['rack.request.query_string']
    else
        raw = request.body.read
    end
    ids = raw.scan(/i=([^&]*)/)
    ids.each_with_index do |id, index|
        id = id[0]
        # we got a long legacy id and need to get the real entry id, but we always want to remove the array
        ids[index] = id.gsub("tag%3Agoogle.com%2C2005%3Areader%2Fitem%2F", "")
    end
    entries = []
    ids.each{|id| entries.push(Entry.new(id: id)) }
    return entries
end

## feedtragon web ##

post '/subscribe' do
    protected!
    # the superfeedr middleware needs to be set if we are not running on /, and it needs to be relative
    Rack::Superfeedr.base_path = url("/superfeedr/feed/", false)
    subscribe(url: params[:url], name: params[:url])
    redirect url '/'
end

post '/unsubscribe' do
    protected!
    Rack::Superfeedr.base_path = url("/superfeedr/feed/", false)
    begin
        params["feeds"].each do |id, _|
            feed = Feed.new(id: id)
            Rack::Superfeedr.unsubscribe(feed.url, id)
            feed.unsubscribed!
        end
    rescue => error
        warn "unsubscribe: #{error}"
    end
    redirect url '/settings'
end

post '/import' do
    protected!
    Rack::Superfeedr.base_path = url("/superfeedr/feed/", false)
    opml = params[:file][:tempfile].read
    doc = Nokogiri::XML(opml)
    doc.xpath("/opml/body/outline").map do |outline|
        begin
            subscribe(url: outline.attr("xmlUrl"), name: outline.attr("title"))
        rescue Net::ReadTimeout
            warn "could not subscribe to #{outline.attr("xmlUrl")}"
        end
    end
    redirect url '/'
end

get '/feeds.opml' do
    protected!
    content_type 'text/x-opml'
    erb :export, :layout => false, :locals => {:feeds => Database.new.getFeeds(onlyUnread: false) }
end

def subscribe(url:, name:)
    protected!
    feed = Feed.new(url: url, name: name).save!
    if ! feed.subscribed?
        Rack::Superfeedr.subscribe(feed.url, feed.id, {retrieve: true, format: 'json'}) do |body, success, response|
            if success
                feed.subscribed!
                return feed
            else
                warn "error subscribing"
                warn response
                warn body
            end
        end
    end
end

post %r{/([0-9]+)/read} do |id|
    protected!
    Entry.new(id: id).read!
    return id
end

post %r{/([0-9]+)/unread} do |id|
    protected!
    Entry.new(id: id).unread!
    return id
end

post %r{/([0-9]+)/mark} do |id|
    protected!
    Entry.new(id: id).mark!
    return id
end

post %r{/([0-9]+)/unmark} do |id|
    protected!
    Entry.new(id: id).unmark!
    return id
end

post '/readall' do
    protected!
    params[:ids].each {|id| Entry.new(id: id).read!} if params[:ids]
    Database.new.readall if params[:all]
    redirect url '/'
end

get %r{/([0-9]+)/feedlink} do |id|
    protected!
    erb :feedlink, :layout => false, :locals => {:feed => Feed.new(id: id), :current_feed_id => nil}
end

get %r{/([0-9]+)/entry} do |id|
    protected!
    erb :entry, :layout => false, :locals => {:entry => Entry.new(id: id)}
end

get %r{/(.*)/entries} do |feed_id|
    protected!
    entries = []
    if (feed_id == "marked")
        feed_entries = Database.new.getMarkedEntries(params[:startId])
    else 
        feed_entries = Feed.new(id: feed_id).entries(startId: params[:startId])
    end
    feed_entries.each{|entry| entries.push(erb :entry, :layout => false, :locals => {:entry => entry})}
    {:entries => entries}.to_json
end

post '/addSuperfeedr' do
    protected!
    db = Database.new
    db.setOption("host",  params["host"] || request.host)
    db.setOption("superfeedrName", params["name"])
    db.setOption("superfeedrPassword", params["password"])
    db.setOption("secret", SecureRandom.urlsafe_base64(256)) if ! db.getOption("secret")
    loadConfiguration()
    redirect url '/'
end


post '/setPassword' do
    protected!
    db = Database.new
    hasher = Argon2::Password.new
    hashed_password = hasher.create(params["clientPassword"])
    # Argon2::Password.verify_password(password, Database.new.getOption("clientPassword"))
    db.setOption("clientPassword", hashed_password)
    redirect url '/'
end

websocket '/updated' do
    protected!
    ws.onmessage do |msg| 
        feedid = JSON.parse(msg)["feedid"].to_i
        websockets[feedid] ? websockets[feedid] << ws : websockets[feedid] = [ws]
    end
    ws.onclose do
        websockets.each {|websocket| websocket.delete(ws) if websocket}
    end
    "Done"
end

get %r{/(.*)/feed} do |feed_url|
    halt 404 if feed_url != gen_secret_url.to_s
    headers "Content-Type"   => "application/rss+xml"
    erb :feed, :layout => false, :locals => {:entries => Database.new.getMarkedEntries(nil)}
end

get %r{/([0-9]+)} do |id|
    erb :entrylist, :locals => {:feeds => Database.new.getFeeds(onlyUnread: true), :entries => Feed.new(id: id).entries(startId: params[:startId]), :current_feed_id => id}
end

get '/settings' do
    erb :settings, :locals => {:feeds => Database.new.getFeeds, :entries => nil, :current_feed_id => nil, :allFeeds => Database.new.getFeeds(onlyUnread: false)}
end

get '/marked' do
    erb :entrylist, :locals => {:feeds => Database.new.getFeeds, :entries => Database.new.getMarkedEntries(params[:startId]), :current_feed_id => 'marked'}
end

get '/' do
    if Database.new.firstUse? || ! Database.new.superfeedrLinked?
        Database.new.addUser('admin', authorized_email) if ! authorized_email.nil?
        erb :installer, :layout => false
    else
        erb :index, :locals => {:feeds => Database.new.getFeeds(onlyUnread: true), :current_feed_id => nil}
    end
end