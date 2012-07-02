$stdout.sync = true
ENV["RACK_ENV"] ||= "development"
$production = ENV["RACK_ENV"] == 'production'

require 'rubygems'
require 'bundler'
Bundler.setup
Bundler.require(:default, ENV["RACK_ENV"].to_sym)
require 'active_record'
require 'logger'
require 'sinatra/base'
require 'rack/websocket'
require 'uri'
require 'cgi'
require 'rexml/document'

JS_CACHE = {}

# Init Environment

APP_CONFIG = YAML.load(File.read('config/app.yml'))[ENV["RACK_ENV"]] || {}

dbconfig = YAML.load(File.read('config/database.yml'))
#Time.zone = 'UTC'
ActiveRecord::Base.time_zone_aware_attributes = true
ActiveRecord::Base.default_timezone = :utc
if ENV["RACK_ENV"] == 'test'
  ActiveRecord::Base.logger = Logger.new(File.open('test.log', 'w'))
else
  ActiveRecord::Base.logger = Logger.new(STDOUT)
end

JSON.create_id = nil

%w{app models subscribers redis_subscriber_list web_socket_app util}.each do |lib|
  require File.join(File.dirname(__FILE__), lib)
end

ActiveRecord::Base.establish_connection dbconfig[ENV['RACK_ENV']]


# Redis
if ENV['TUBEHUB_MODE'] == 'frontend'
  SUBSCRIPTIONS = RedisSubscriberList.new
else
  SUBSCRIPTIONS = SubscriberList.new
end

$redis = nil
$redis_listen = nil

EM.next_tick do
  SUBSCRIPTIONS.setup
  SUBSCRIPTIONS.start_timer
end unless ENV["RACK_ENV"] == 'test'
