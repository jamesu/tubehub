require 'rubygems'
require 'bundler'
Bundler.require
require 'active_record'
require 'logger'
require 'sinatra/base'
require 'rack/websocket'
require 'uri'
require 'cgi'

class User < ActiveRecord::Base
  before_validation :set_tokens
  attr_accessor :password
  
  def set_tokens
    if @password
      tnow = Time.now()
      sec = tnow.tv_usec
      usec = tnow.tv_usec % 0x100000
      rval = rand()
      roffs = rand(25)
      self[:salt] = Digest::SHA1.hexdigest(sprintf("%s%08x%05x%.8f", rand(32767), sec, usec, rval))[roffs..roffs+12]
      self[:token] = Digest::SHA1.hexdigest(salt + @password)
    end
  end
  
  def generate_auth_token!
    tnow = Time.now()
    sec = tnow.tv_usec
    usec = tnow.tv_usec % 0x100000
    rval = rand()
    roffs = rand(25)
    self[:auth_token] = Digest::SHA1.hexdigest(Digest::SHA1.hexdigest(sprintf("%s%08x%05x%.8f", rand(32767), sec, usec, rval))[roffs..roffs+12])
    save!
  end
  
  def self.authenticate(name, password)
    user = User.find_by_name(name)
    if user && Digest::SHA1.hexdigest(user.salt + password) == user.token
      user
    else
      nil
    end
  end
end

class Channel < ActiveRecord::Base
  belongs_to :user
end

class Video < ActiveRecord::Base
  belongs_to :channel
  belongs_to :user
end

dbconfig = YAML.load(File.read('config/database.yml'))
ActiveRecord::Base.establish_connection dbconfig['development']

JSON.create_id = nil

SUBSCRIPTIONS = {}

class WebSocketApp < Rack::WebSocket::Application
  
  def on_open(env)
    # We cant rely on cookies so wait for the auth message
  end
  
  def on_message(env, data)
    message = JSON.parse(data) rescue {}
    user_id = @current_user ? @current_user.name : 'Anonymous'
    puts "#{user_id}: #{message.inspect}"
    
    case message['type']
    when 'auth'
      user = User.find_by_auth_token(message['auth_token'])
      if user && user.auth_token?
        puts "OPEN user == #{user.inspect}"
        @current_user = user
        #send_data({'type' => 'users', 'users' => SOCKET_CONNECTIONS.map{|s|s.@current_user.name}.uniq}.to_json)
        send_data({'type' => 'hello', 'user' => @current_user.name}.to_json)
        @current_user.update_attribute(:auth_token, nil)
      else
        send_data({'type' => 'hello', 'user' => 'Anonymous'}.to_json)
      end
    when 'subscribe'
      channel = Channel.find_by_id(message['channel_id'])
      if channel
        puts "SUBSCRIBING TO CHANNEL #{channel.name}"
        SUBSCRIPTIONS[channel.id] ||= []
        SUBSCRIPTIONS[channel.id].each{|socket| socket.send_data({'type' => 'userjoined', 'user' => user_id}.to_json)}
        SUBSCRIPTIONS[channel.id] << self
        puts channel.inspect
        puts @current_user.inspect
        user_scope = (@current_user and @current_user.id == channel.user_id) ? ['admin'] : []
        send_data({'type' => 'userjoined', 'user' => user_id, 'scope' => user_scope}.to_json)
      end
    when 'unsubscribe'
      channel = Channel.find_by_id(message['channel_id'])
      if channel && SUBSCRIPTIONS[channel.id]
        SUBSCRIPTIONS[channel.id].each{|socket| socket.send_data({'type' => 'userleft', 'user' => user_id}.to_json)}
        SUBSCRIPTIONS[channel.id].delete(self)
      end
    when 'video'
      return if @current_user.nil?
      # Only the owner of the channel can set the video
      location = URI.parse(message['url']) rescue nil
      video_id = if location
        CGI.parse(location.query)['v']
      end
      
      subscribers = SUBSCRIPTIONS[message['channel_id']]
      if video_id && subscribers
        channel = Channel.find_by_id(message['channel_id'])
        if channel.user == @current_user
          subscribers.each do |subscriber|
            subscriber.send_data({'type' => 'video', 'url' =>  video_id, 'time' => message['time']}.to_json)
          end
        end
      end
    when 'video_time'
      return if @current_user.nil?
      # Only the owner of the channel can set the video_time
      subscribers = SUBSCRIPTIONS[message['channel_id']]
      if subscribers
        puts "SENDING TO: #{SUBSCRIPTIONS[message['channel_id']].map(&:object_id).join(',')}"
        channel = Channel.find_by_id(message['channel_id'])
        if channel.user == @current_user
          subscribers.each do |subscriber|
            subscriber.send_data({'type' => 'video_time', 'time' => message['time']}.to_json)
          end
        end
      end
    end
  end
  
  def on_close(env)
    puts "CLOSE"
  end
end

class App < Sinatra::Base
  set :public, File.dirname(__FILE__) + '/public'
  set :static, true

  def initialize(app=nil)
    super(app)
  end

  def current_user
    @current_user ||= User.find_by_id(session[:user_id]) if session[:user_id]
  end

  def login_required
    if current_user.nil?
      redirect '/auth'
      halt
    end
  end

  get '/' do
    # Display the first channel for now
    @channel = Channel.first
    erb :channel
  end

  get '/auth' do
    erb :login
  end

  post '/auth' do
    if params[:error]
      render 'error'
    else
      # get token
      @current_user = User.authenticate(params[:name], params[:password])
      if @current_user
        session[:user_id] = @current_user.id
        redirect session[:return_to] || '/'
      else
        erb :error
      end
    end
  end
  
  post '/auth/socket_token' do
    login_required
    current_user.generate_auth_token!
    content_type :json
    {:auth_token => current_user.auth_token}.to_json
  end
end


