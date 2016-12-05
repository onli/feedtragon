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
require 'thread/pool'
require 'throttle-queue'
include ERB::Util
set :static_cache_control, [:public, max_age: 31536000]
register Sinatra::Hijacker
# disable path_traversal for greader api, remote token for persona behind nginx proxy
use Rack::Protection, except: [:path_traversal, :remote_token]

websockets = []
class FlowControl
    # FlowControl contains the global threadpool and throttle used to move jobs to the background, like importing feeds
    def self.init
        @@pool = Thread.pool(3)
        @@throttle = ThrottleQueue.new 1
    end

    def self.pool
        return @@pool
    end

    def self.throttle
        return @@throttle
    end
end

class Clogger
    # Clogger is a wrapper containing a logger. This is necessary to be able to use the same logfile for
    # sinatra request logging and custom logging by calling sinatras logger
    def self.init(production)
        if production
            Dir.mkdir('logs') unless File.exist?('logs')
            @@logger = Logger.new('logs/common.log','weekly')
        else
            @@logger = Logger.new(STDOUT)
        end
    end

    def self.info(x)
        @@logger.info(x)
    end

    def self.error(x)
        @@logger.error(x)
    end

    def self.logger
        return @@logger
    end
end


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

    def isRegistered?
        if authorized?
            return Database.new.registered?(authorized_email)
        end
    end

    def protected!
        unless isRegistered?
            halt 401, erb(:login, :locals => {:feeds => nil, :current_feed_id => nil})
        end
    end

    def adminProtected!
        if (isRegistered? && isAdmin?)
            return true
        else
            halt 401, erb(:login, :locals => {:feeds => nil, :current_feed_id => nil})
        end
    end

    def truncate(text, length, append)
        return text.gsub(/^(.{#{length},}?).*$/m,'\1' + append)
    end

    def secret_url
        return (Database.new.getOption(authorized_email + "_secret") or gen_secret_url)
    end

    def getOption(name)
        Database.new.getOption(name)
    end

    # returns user email as string if access is granted, false otherwise
    def apiAccess!(token = nil)
        if token
            # is there a ctoken[0..63] in the dababase that equals token
            return Database.new.getUserByToken(token, 64) # note: the token only fits 64 chars
        else
            # is there a ctoken in the dababase that equals HTTP_AUTHORIZATION
            ctoken = request.env["HTTP_AUTHORIZATION"].gsub('GoogleLogin auth=', '')
            return Database.new.getUserByToken(ctoken)
        end
        return false
    end
end

def loadConfiguration()
    db = Database.new
    Rack::Superfeedr.host = db.getOption("host")
    Rack::Superfeedr.login = db.getOption("superfeedrName")
    Rack::Superfeedr.password = db.getOption("superfeedrPassword")
    Rack::Superfeedr.scheme = "https"
end

def gen_secret_url()
    begin
        db = Database.new
        db.setOption(authorized_email + "_secret", SecureRandom.urlsafe_base64(256)) if ! db.getOption(authorized_email + "_secret")
        return Digest::RMD160.new << db.getOption(authorized_email + "secret")
    rescue TypeError
        return ""
    end
end

configure do
    loadConfiguration()
    set :protection, :except => [:path_traversal]
    FlowControl::init
    disable :logging
    Clogger::init(settings.production?)
    if (settings.production?)
        use Rack::CommonLogger, Clogger::logger
    end
end

use Rack::Superfeedr do |superfeedr|
    superfeedr.on_notification do |feed_id, body, url, request|
        feed_id = feed_id.to_i
        Database.new.log(name: "notification", log: body.to_s) if ! settings.production?
        notification = JSON.parse(body)
        Feed.new(id: feed_id, user: nil).setName(name: notification["title"]) if notification["title"] && ! notification["title"].empty?
        if notification["items"]
            websockets.each {|feedsockets| feedsockets.each {|feedsocket| feedsocket.send_data({:updated_feed => feed_id}.to_json)} if feedsockets }
            notification["items"].each do |item|
                content = item["content"] || item["summary"]
                content = item["content"].length > item["summary"].length ? item["content"] : item["summary"]  if item["content"] && item["summary"]
                entry = Entry.new(url: item["permalinkUrl"], title: item["title"], content: content, feed_id: feed_id, user: nil).save!
                websockets[feed_id].each {|feedsocket| feedsocket.send_data({:new_entry => entry.id}.to_json) if feedsocket} if websockets[feed_id]
            end
        else
            feed = Feed.new(id: feed_id, user: nil)
            if notification["status"]["code"] != 0 &&
                (Time.now - Time.at(notification["status"]["lastParse"])) > (60 * 60 * 24 * 20) &&
                (Time.now - Time.at(feed.lastUpdated)) > (60 * 60 * 24 * 20)
                # this was not just a ping, which signals the feed is broken for superfeedr
                # and for more than 20 days superfeedr was unable to parse this
                # and our last internal update is older than 20 days
                # then we unsubscribe, to reduce load
                Clogger::info "automatic unsubscribing #{feed_id}"
                Rack::Superfeedr.unsubscribe url, feed_id do |n|
                    Clogger::info "unsubscribed feed"
                    feed.unsubscribe!
                end
            end
        end
    end
end

## bazqux flavored reader api ##

require './greader.rb'

## feedtragon web ##

post '/logout' do
    logout!
    redirect '/'
end

post '/subscribe' do
    protected!
    # the superfeedr middleware needs to be set if we are not running on /, and it needs to be relative
    Rack::Superfeedr.base_path = url("/superfeedr/feed/", false)
    subscribe(url: params[:url], name: params[:url], user: authorized_email)
    redirect url '/'
end

post '/rename' do
    protected!
    feed = Feed.new(id: params[:feed], user: authorized_email).setName(name: URI.decode_www_form_component(params[:name]))
end

post '/category' do
    protected!
    feed = Feed.new(id: params[:feed], user: authorized_email)
    if params[:category] == "newCategory"
        feed.setCategory(category: params[:newCategory])
    else
        feed.setCategory(category: params[:category])
    end
    redirect back
end

get '/categoryForm' do
    protected!
    erb :categoryForm, :layout => false, :locals => {:feed => Feed.new(id: params[:feed], user: authorized_email), :categories => Database.new.getCategories(user: authorized_email)}
end

post '/unsubscribe' do
    protected!
    Rack::Superfeedr.base_path = url("/superfeedr/feed/", false)
    FlowControl::pool.process {
        begin
            params["feeds"].each do |id, _|
                feed = Feed.new(id: id, user: authorized_email)
                feed.unsubscribeUser!
                Clogger::info "unsubscribed feed #{id} for #{authorized_email}"
                if (feed.subscribers == 0)
                    FlowControl::throttle.background(id) {
                        Rack::Superfeedr.unsubscribe(feed.url, id) do |n|
                            Clogger::info "unsubscribed feed #{id} at superfeedr!"
                            Feed.new(id: feed.id, user: nil).unsubscribe!
                        end
                    }
                end
            end
        rescue => error
            Clogger::error "unsubscribe: #{error}"
        end
    }
    redirect url '/#msgUnsubscribe'
end

post '/import' do
    protected!
    Rack::Superfeedr.base_path = url("/superfeedr/feed/", false)
    opml = params[:file][:tempfile].read
    doc = Nokogiri::XML(opml)
    FlowControl::pool.process {
        Clogger::info "starting import for #{authorized_email}"
        doc.xpath("/opml/body/outline").map do |first_level_outline|
            begin
                if first_level_outline.attr("xmlUrl")
                    # a feed
                    subscribe(url: first_level_outline.attr("xmlUrl"), name: first_level_outline.attr("text"), user: authorized_email)
                else
                    # it is a category
                    first_level_outline.children.each do |outline|
                        if outline.attr("xmlUrl") # because the xpath also selects the first_level_group itself
                            begin
                                subscribe(url: outline.attr("xmlUrl"), name: outline.attr("text"), user: authorized_email, category: first_level_outline.attr("text")) 
                            rescue Net::ReadTimeout
                                Clogger::error "could not subscribe to #{outline.attr("xmlUrl")}, timeout"
                            end
                        end
                    end
                end
            rescue Net::ReadTimeout
                Clogger::error "could not subscribe to #{outline.attr("xmlUrl")}, timeout"
            end
        end
        FlowControl::throttle.wait
    }
    redirect url '/#msgImport'
end

get '/feeds.opml' do
    protected!
    content_type 'text/x-opml'
    erb :export, :layout => false, :locals => {:feeds => Database.new.getFeeds(onlyUnread: false, user: authorized_email) }
end

def subscribe(url:, name:, user:, category: nil)
    protected!
    Clogger::info "start subscribing #{url} for #{user}"
    feed = Feed.new(url: url, name: name, user: user, category: category).save!
    if ! feed.subscribed?
        FlowControl::throttle.background(url) {
            Rack::Superfeedr.subscribe(feed.url, feed.id, {retrieve: true, format: 'json'}) do |body, success, response|
                if success
                    feed.subscribed!
                    Clogger::info "successfully subscribed #{url} in feed #{feed.id.to_s}"
                    begin
                        oldEntries = ::JSON.parse(body)
                        oldEntries['items'].each do |item|
                            content = item["content"] || item["summary"]
                            content = item["content"].length > item["summary"].length ? item["content"] : item["summary"]  if item["content"] && item["summary"]
                            Entry.new(url: item["permalinkUrl"], title: item["title"], content: content, feed_id: feed.id, user: nil).save!
                        end
                    rescue => e
                        Clogger::error "could not parse old entries after subscribing: #{e}"
                    end
                    return feed
                else
                    Clogger::error "error subscribing #{url}"
                    Clogger::error response
                    Clogger::error body
                end
            end
        }
    end
end

post %r{/([0-9]+)/read} do |id|
    protected!
    Entry.new(id: id, user: authorized_email).read!
    return id
end

post %r{/([0-9]+)/unread} do |id|
    protected!
    Entry.new(id: id, user: authorized_email).unread!
    return id
end

post %r{/([0-9]+)/mark} do |id|
    protected!
    Entry.new(id: id, user: authorized_email).mark!
    return id
end

post %r{/([0-9]+)/unmark} do |id|
    protected!
    Entry.new(id: id, user: authorized_email).unmark!
    return id
end

post '/readall' do
    protected!
    params[:ids].each {|id| Entry.new(id: id, user: authorized_email).read!} if params[:ids]
    Database.new.readall(user: authorized_email) if params[:all]
    redirect url '/'
end

get %r{/([0-9]+)/feedlink} do |id|
    protected!
    erb :feedlink, :layout => false, :locals => {:feed => Feed.new(id: id, user: authorized_email), :current_feed_id => nil}
end

get %r{/([0-9]+)/entry} do |id|
    protected!
    erb :entry, :layout => false, :locals => {:entry => Entry.new(id: id, user: authorized_email)}
end

get %r{/(.*)/entries} do |feed_id|
    protected!
    entries = []
    if (feed_id == "marked")
        feed_entries = Database.new.getMarkedEntries(params[:startId], user: authorized_email)
    else 
        feed_entries = Feed.new(id: feed_id, user: authorized_email).entries(startId: params[:startId])
    end
    feed_entries.each{|entry| entries.push(erb :entry, :layout => false, :locals => {:entry => entry})}
    {:entries => entries}.to_json
end

post '/addSuperfeedr' do
    adminProtected!
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
    db.setOption(authorized_email + "_clientPassword", hashed_password)
    redirect url '/'
end

post '/setUsers' do
    adminProtected!
    db = Database.new
    users = params[:users]["mail"]
    users.each do |_, mail|
        db.addUser("", mail.strip)
    end
    redirect url '/admin'
end

websocket '/updated' do
    protected!
    ws.onmessage do |msg|
        # TODO: notify only subscribers to that feed
        feedid = JSON.parse(msg)["feedid"].to_i
        websockets[feedid] ? websockets[feedid] << ws : websockets[feedid] = [ws]
    end
    ws.onclose do
        websockets.each {|websocket| websocket.delete(ws) if websocket}
    end
    "Done"
end

get %r{/(.*)/feed} do |feed_url|
    db = Database.new
    unless (db.getOption(params[:user] + "_secret") == feed_url) 
        halt 404
    end
    headers "Content-Type"   => "application/rss+xml"
    erb :feed, :layout => false, :locals => {:entries => Database.new.getMarkedEntries(nil, user: params[:user])}
end

get %r{/([0-9]+)} do |id|
    protected!
    currentFeed = Feed.new(id: id, user: authorized_email)
    erb :entrylist, :locals => {:feeds => Database.new.getFeeds(onlyUnread: true, user: authorized_email), :entries => currentFeed.entries(startId: params[:startId]), :current_feed_id => id, :current_category => currentFeed.category}
end

get '/settings' do
    protected!
    erb :settings, :locals => {:feeds => Database.new.getFeeds(user: authorized_email), :entries => nil, :current_feed_id => nil, :allFeeds => Database.new.getFeeds(onlyUnread: false, user: authorized_email)}
end

get '/admin' do
    adminProtected!
    db = Database.new
    erb :admin, :locals => {:feeds => db.getFeeds(user: authorized_email), :entries => nil, :current_feed_id => nil, :users => db.getUsers}
end


get '/marked' do
    protected!
    erb :entrylist, :locals => {:feeds => Database.new.getFeeds(user: authorized_email), :entries => Database.new.getMarkedEntries(params[:startId], user: authorized_email), :current_feed_id => 'marked'}
end

get '/' do
    if Database.new.firstUse? || ! Database.new.superfeedrLinked?
        Database.new.addUser('admin', authorized_email) if ! authorized_email.nil?
        erb :installer, :layout => false
    else
        protected!
        erb :index, :locals => {:feeds => Database.new.getFeeds(onlyUnread: true, user: authorized_email), :current_feed_id => nil}
    end
end
