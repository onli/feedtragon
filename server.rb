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
require 'nokogiri'
use Rack::Session::Pool

helpers do
    def isAdmin?
        if authorized?
            if Database.new.getAdminMail == authorized_email
                return true
            end
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
        Database.new.log(name: "notification", log: body.to_s) if ! settings.production?
        notification = JSON.parse(body)
        if notification["items"] 
            JSON.parse(body)["items"].each do |item|
               Entry.new(url: item["permalinkUrl"], title: item["title"], content: item["content"], feed_id: feed_id).save!
            end
        else
            if (Time.now - Time.at(notification["status"]["lastParse"])) > 604800
                # for more than a week superfeedr was unable to parse this, so we need to unsubscribe to reduce load
                Rack::Superfeedr.unsubscribe url, feed_id do |n|
                    Feed.new(id: feed_id).unsubscribed!
                end
            end
        end
    end
end

post '/subscribe' do
    protected!
    subscribe(url: params[:url], name: params[:url])
end

post '/import' do
    protected!
    opml = params[:file][:tempfile].read
    doc = Nokogiri::XML(opml)
    doc.xpath("/opml/body/outline").map do |outline|
        subscribe(url: outline.attr("xmlUrl"), name: outline.attr("title"))
    end
    return "Import done!"
end

def subscribe(url:, name:)
    protected!
    feed = Feed.new(url: url, name: name).save!
    return "Error! Already subscribed?" if feed.id.nil?
    Rack::Superfeedr.subscribe(feed.url, feed.id, {retrieve: true, format: 'json'}) do |body, success, response|
        feed.subscribed!
    end
end

post %r{/([0-9]+)/read} do |id|
    protected!
    Entry.new(id: id).read!
end

get %r{/([0-9]+)} do |id|
    protected!
    erb :index, :locals => {:feeds => Database.new.getFeeds, :entries => Feed.new(id: id).entries}
end

post '/addSuperfeedr' do
    protected!
    db = Database.new
    db.setOption("host", params["host"])
    db.setOption("superfeedrName", params["name"])
    db.setOption("superfeedrPassword", params["password"])
    db.setOption("secret", SecureRandom.urlsafe_base64(256))
    loadConfiguration()
    redirect to('/')
end

get '/' do
    if Database.new.firstUse? || ! Database.new.superfeedrLinked?
        if ! authorized_email.nil?
            Database.new.addUser('admin', authorized_email)
        end
        erb :installer
    else
        erb :index, :locals => {:feeds => Database.new.getFeeds, :entries => nil}
    end
end

