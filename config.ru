require 'rubygems'
require 'bundler'

Bundler.require

### Enable persistent sessions using moneta ###
require 'moneta'
require 'rack/session/moneta'

DataMapper.setup(:default, (ENV['DATABASE_URL'] || "sqlite://#{Dir.pwd}/sessions.db"))

use Rack::Session::Moneta,
    expire_after: 259200000,
    store: Moneta.new(:DataMapper, setup: (ENV['DATABASE_URL'] || "sqlite://#{Dir.pwd}/sessions.db"))
###

require './server.rb'
run Sinatra::Application