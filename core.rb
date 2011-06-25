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
  attr_accessor :last_set_time
  
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
  belongs_to :current_video, :class_name => 'Video'
  has_many :videos
  
  # Update to new time (e.g. when user has manipulated slider)
  def delta_start_time!(new_time, from=Time.now.utc)
    self.start_time = from - new_time
    save
  end
  
  def current_time(from=Time.now.utc)
    start_time ? from - start_time : 0
  end
  
  def update_active_video!(the_video, new_time=0, from=Time.now.utc)
    self.current_video = the_video
    self.start_time = from - new_time
    save
  end
end

class Video < ActiveRecord::Base
  belongs_to :channel
  belongs_to :user
  
  BLIP_MATCH = /\/play\/(.*)/
  def self.get_playback_info(url)
    location = URI.parse(url) rescue nil
    host = location ? location.host : ''
    query = location ? CGI.parse(location.query) : {} rescue {}
    
    provider, video_id = case host
    when 'blip.tv'
      match = location.path.match(BLIP_MATCH)
      match ? ['blip', match[1]] : ['blip', nil]
    when 'youtube.com'
      ['youtube', query['v'].to_s]
    when 'www.youtube.com'
      ['youtube', query['v'].to_s]
    else
      [nil, '']
    end
    
    {:video_id => video_id, :time => 0, :provider => provider}
  end
end

dbconfig = YAML.load(File.read('config/database.yml'))
Time.zone = 'UTC'
ActiveRecord::Base.time_zone_aware_attributes = true
ActiveRecord::Base.default_timezone = :utc
ActiveRecord::Base.establish_connection dbconfig['development']

JSON.create_id = nil

SUBSCRIPTIONS = {}

class WebSocketApp < Rack::WebSocket::Application
  
  def on_open(env)
    # We cant rely on cookies so wait for the auth message
  end
  
  def send_message(data)
    send_data data.to_json
  end
  
  def on_message(env, data)
    begin
      process_message(env, data)
    rescue Exception => e
      puts "EXCEPTION: #{e.inspect}"
    end
  end
  
  def process_message(env, data)
    message = JSON.parse(data) rescue {}
    user_id = @current_user ? @current_user.name : 'Anonymous'
    puts "#{user_id}: #{message.inspect}"
    now = Time.now.utc
    
    case message['type']
    when 'auth'
      user = User.find_by_auth_token(message['auth_token'])
      if user && user.auth_token?
        puts "OPEN user == #{user.inspect}"
        @current_user = user
        send_message({'type' => 'hello', 'user' => @current_user.name})
        @current_user.update_attribute(:auth_token, nil)
      else
        send_message({'type' => 'hello', 'user' => 'Anonymous'})
      end
    when 'subscribe'
      channel = Channel.find_by_id(message['channel_id'])
      if channel
        puts "SUBSCRIBING TO CHANNEL #{channel.name}"
        SUBSCRIPTIONS[channel.id] ||= []
        SUBSCRIPTIONS[channel.id].each{|socket| socket.send_message({'type' => 'userjoined', 'user' => user_id})}
        SUBSCRIPTIONS[channel.id] << self
        user_scope = (@current_user and @current_user.id == channel.user_id) ? ['admin'] : []
        send_message({'type' => 'userjoined', 'user' => user_id, 'scope' => user_scope})
        
        # Get current video
        if channel.current_video
          puts "VIDEO? #{channel.current_video.url} #{channel.current_video.provider}"
          send_message({'type' => 'video',
                        'url' => channel.current_video.url,
                        'provider' => channel.current_video.provider,
                        'time' => channel.current_time})
        end
      end
    when 'unsubscribe'
      channel = Channel.find_by_id(message['channel_id'])
      if channel && SUBSCRIPTIONS[channel.id]
        SUBSCRIPTIONS[channel.id].each{|socket| socket.send_message({'type' => 'userleft', 'user' => user_id})}
        SUBSCRIPTIONS[channel.id].delete(self)
      end
    when 'video'
      return if @current_user.nil?
      # Only the owner of the channel can set the video
      video_info = Video.get_playback_info(message['url'])
      
      subscribers = SUBSCRIPTIONS[message['channel_id']]
      if video_info[:provider] && !video_info[:video_id].empty? && subscribers
        channel = Channel.find_by_id(message['channel_id'])
        if channel.user == @current_user
          # Update channel video
          video = if channel.current_video.nil?
            channel.videos.build(:url => video_info[:video_id], :provider => video_info[:provider])
          else
            channel.current_video.update_attributes(:url => video_info[:video_id], :provider => video_info[:provider])
            channel.current_video
          end
          channel.update_active_video!(video, message['time']||0, now)
          # Tell everyone
          subscribers.each do |subscriber|
            subscriber.send_message({'type' => 'video',
                                     'provider' => video_info[:provider],
                                     'url' => video_info[:video_id],
                                     'time' => message['time']||0})
          end
        end
      end
    when 'video_time'
      return if @current_user.nil?
      subscribers = SUBSCRIPTIONS[message['channel_id']]
      if subscribers
        puts "SENDING TO: #{SUBSCRIPTIONS[message['channel_id']].map(&:object_id).join(',')}"
        channel = Channel.find_by_id(message['channel_id'])
        if !message['time'].nil? and channel.user == @current_user
          # Adjust channel model time if delta is too large
          current_time = channel.current_time(now)
          if (current_time - message['time'] < -1.0) or (current_time - message['time'] > 1.0)
            puts "ADJUSTING CHANNEL TIME: #{message['time']} vs #{current_time} / #{channel.current_time(now)} #{current_time - message['time']}"
            channel.delta_start_time!(message['time'], now)
          end
          # Tell everyone the current time
          subscribers.each do |subscriber|
            subscriber.send_message({'type' => 'video_time', 'time' => message['time']})
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


