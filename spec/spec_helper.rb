ENV['RACK_ENV'] = 'test'

require "#{File.dirname(__FILE__)}/../core"
require 'rspec'
require 'rack/test'

# Use the following mixin to wire up rack/test and sinatra
module RSpecMixin
  include Rack::Test::Methods
  def app() App.new end
end

RSpec.configure do |c| 
  c.include RSpecMixin
end

def mock_session(env={})
  {'rack.session' => env}
end

def mock_login(user)
  {:user_id => user.id}
end

def mock_login_session(user)
  mock_session(mock_login(user))
end

# Disable send_data for mocking
class WebSocketApp < Rack::WebSocket::Application
  def send_data(data)
  end
  
  def send_message(msg)
  end
  
  def close_websocket
  end
end

# Disable metadata grabbing
class Video
  def grab_metadata
  end
end

class FakeConnection
  attr_accessor :messages, :current_user, :scope
  attr_accessor :skip, :leader, :auth
  attr_accessor :addresses
  
  def initialize(user=nil, name=nil, tripcode=nil, ips=nil)
    @current_user = user
    @current_name = name
    @current_tripcode = tripcode
    @addresses = ips||[]
  end
  
  def send_message(msg)
    @messages||=[]
    @messages << msg
  end
  
  def current_channel_id
    @current_channel_id
  end
  
  def user_id
    @current_user ? "user_#{@current_user.id}" : "anon_#{object_id}"
  end
  
  def user_name
    @current_user ? @current_user.name : @current_name
  end
  
  def user_data
    {:id => user_id, :name => user_name, :tripcode => @current_tripcode, :anon => @current_user ? false : true, :leader => @leader ? false : true}
  end
  
  def scope_for(channel)
    if @scope_chan != channel
      @scope = nil
      @scope_chan = channel
    end
    
    if @scope.nil?
      if @current_user && @current_user.admin
        @scope = 'sumin'
      elsif @current_user && channel.admin_channels.include?(@current_user)
        @scope = 'admin'
      elsif channel.moderators.find_by_name("#{user_name}#{@current_tripcode}")
        @scope = 'mod'
      else
        @scope = ''
      end
    end
    @scope
  end
  
  def close_websocket
  end
end

BASE_VIDEO_INFO = 
    {'id' => 1,
     'url' => 'H0MwvOJEBOM',
     'provider' => 'dummy',
     'title' => 'HOW 2 DRAW SANIC HEGEHOG',
     'duration' => 0,
     'playlist' => false,
     'position' => nil,
     'added_by' => 'Anonymous'}


