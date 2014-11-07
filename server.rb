#!/usr/bin/env ruby
require 'rubygems'

require './feed.rb'
require './entry.rb'
require './database.rb'

require 'sinatra'
require 'rack-superfeedr'
require 'json'
require 'sinatra/url_for'
require 'sinatra/browserid'
require 'sinatra/hijacker'
require 'nokogiri'
use Rack::Session::Pool
register Sinatra::Hijacker

websockets = []

helpers do
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
end

def loadConfiguration()
    db = Database.new
    Rack::Superfeedr.host = db.getOption("host")
    Rack::Superfeedr.login = db.getOption("superfeedrName")
    Rack::Superfeedr.password = db.getOption("superfeedrPassword")
end

configure do
    loadConfiguration()
end

use Rack::Superfeedr do |superfeedr|
    superfeedr.on_notification do |feed_id, body, url, request|
        feed_id = feed_id.to_i
        Database.new.log(name: "notification", log: body.to_s) if ! settings.production?
        notification = JSON.parse(body)
        Feed.new(id: feed_id).setName(name: notification[:title]) if notification[:title]
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

post '/subscribe' do
    protected!
    subscribe(url: params[:url], name: params[:url])
    redirect to('/')
end

post '/import' do
    protected!
    opml = params[:file][:tempfile].read
    doc = Nokogiri::XML(opml)
    doc.xpath("/opml/body/outline").map do |outline|
        subscribe(url: outline.attr("xmlUrl"), name: outline.attr("title"))
    end
    redirect to('/')
end

def subscribe(url:, name:)
    protected!
    puts "subscribe"
    feed = Feed.new(url: url, name: name).save!
    puts "feed loaded: #{feed.id}"
    if ! feed.subscribed?
        puts "feed not already subscribed"
        Rack::Superfeedr.subscribe(feed.url, feed.id, {retrieve: true, format: 'json'}) do |body, success, response|
            if success
                puts "subscription confirmed"
                feed.subscribed!
            else
                puts "error subscribing"
                puts response
                puts body
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

post '/readall' do
    protected!
    params[:ids].each {|id| Entry.new(id: id).read!} if params[:ids]
    Database.new.readall if params[:all]
    redirect to('/')
end

get %r{/([0-9]+)/feedlink} do |id|
    protected!
    erb :feedlink, :locals => {:feed => Feed.new(id: id), :current_feed_id => nil}
end
get %r{/([0-9]+)/entry} do |id|
    protected!
    erb :entry, :locals => {:entry => Entry.new(id: id)}
end

get %r{/([0-9]+)} do |id|
    erb :index, :locals => {:feeds => Database.new.getFeeds, :entries => Feed.new(id: id).entries, :current_feed_id => id}
end

post '/addSuperfeedr' do
    protected!
    db = Database.new
    db.setOption("host", request.host)
    db.setOption("superfeedrName", params["name"])
    db.setOption("superfeedrPassword", params["password"])
    db.setOption("secret", SecureRandom.urlsafe_base64(256))
    loadConfiguration()
    redirect to('/')
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

get '/' do
    if Database.new.firstUse? || ! Database.new.superfeedrLinked?
        Database.new.addUser('admin', authorized_email) if ! authorized_email.nil?
        erb :installer
    else
        erb :index, :locals => {:feeds => Database.new.getFeeds, :entries => nil, :current_feed_id => nil}
    end
end

