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

# Disable send_data for mocking
class WebSocketApp < Rack::WebSocket::Application
  def send_data(data)
  end
end

# Disable metadata grabbing
class Video
  def grab_metadata
  end
end

class FakeConnection
  attr_accessor :messages, :current_user, :scope
  
  def initialize(user=nil, name=nil, tripcode=nil)
    @current_user = user
    @current_name = name
    @current_tripcode = tripcode
  end
  
  def send_message(msg)
    @messages||=[]
    @messages << msg
  end
  
  def user_id
    @current_user ? "user_#{@current_user.id}" : "anon_#{object_id}"
  end
  
  def user_name
    @current_user ? @current_user.name : @current_name
  end
  
  def user_data
    {:id => user_id, :name => user_name, :tripcode => @current_tripcode, :anon => @current_user ? false : true }
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
end

