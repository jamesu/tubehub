require 'rubygems'
require 'bundler'
Bundler.require
require 'active_record'
require 'logger'
require 'sinatra/base'
require 'rack/websocket'
require 'uri'
require 'cgi'
require 'rexml/document'

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
  
  before_update :set_update_info
  after_update :notify_updates
  
  # Update to new time (e.g. when user has manipulated slider)
  def delta_start_time!(new_time, from=Time.now.utc)
    self.start_time = from - new_time
    save
  end
  
  # Current time based upon channel start time
  def current_time(from=Time.now.utc)
    start_time ? from - start_time : 0
  end
  
  # Go to next video in playlist
  def next_video!
    # Current video in playlist?
    idx = videos.index(current_video)
    if idx.nil? and !videos.empty?
      self.current_video = videos.first
      save
    elsif !video_idx.nil?
      idx += 1
      idx = 0 if idx == videos.length
      self.current_video = videos[idx]
      save
    else
      false
    end
  end
  
  # Plays video in playlist
  def play_item(new_video)
    return if current_video == new_video
    
    if current_video and current_video.playlist == false
      current_video.destroy
    end
    
    @force_video = true
    self.current_video = new_video
    self.start_time = Time.now.utc
    save
  end
  
  # Adds video info, grabs metadata later
  def add_video(video_info, from=Time.now.utc)
    video = videos.build
    
    # Set attributes now
    video.attributes = {:url => video_info[:video_id],
                        :provider => video_info[:provider],
                        :position => videos.count,
                        :playlist => true}
    video.save
    
    video.grab_metadata
    video
  end
  
  # Plays video info, grabs metadata later
  def quickplay_video(video_info, from=Time.now.utc)
    video = if current_video and !current_video.playlist
      current_video
    else
      videos.build({:playlist => false})
    end
    
    # Set attributes now
    video.attributes = {:url => video_info[:video_id], :provider => video_info[:provider]}
    video_saved = video.save
    
    video.grab_metadata
    
    new_time = video_info[:time]||0
    self.current_video = video if video_saved
    self.start_time = from - new_time
  end
  
  def set_update_info
    @video_changed = current_video_id_changed?
    @time_changed = start_time_changed?
    true
  end
  
  def notify_updates
    if @video_changed
      SUBSCRIPTIONS.send_message(id, current_video.to_info.merge({'type' => 'video', 'time' => current_time, 'force' => @force_video||false}))
    elsif @time_changed
      SUBSCRIPTIONS.send_message(id, {'type' => 'video_time', 'time' => current_time})
    end
    @video_changed = @time_changed = false
    true
  end
end

class Video < ActiveRecord::Base
  belongs_to :channel
  belongs_to :user
  
  before_update :set_update_info
  after_save :notify_updates
  after_create :notify_updates
  after_destroy :notify_destroy
  
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
  
  def grab_metadata
    # Grab metadata from provider
    case provider
    when 'youtube'
      grab_youtube_metadata
    when 'blip'
      grab_blip_metadata
    end
  end
  
  def grab_youtube_metadata
    record = self
    # GET http://gdata.youtube.com/feeds/api/videos/:id [entry/title]
    EM::HttpRequest.new("http://gdata.youtube.com/feeds/api/videos/#{url}").get.callback do |http|
      begin
        xml = REXML::Document.new(http.response)
        title = nil
        duration = nil

        xml.elements.each("entry/title") { |t| title = t.text }
        xml.elements.each("entry/media:group/yt:duration") { |t| duration = t.attribute('seconds').value.to_f }

        puts "VIDEO #{url}: TITLE=#{title}, DURATION=#{duration}"
        unless title.nil? and duration.nil?
          record.title = title
          record.duration = duration
          record.save!
        end
      rescue Object => e
        puts "VIDEO #{url}: ERROR GETTING METADATA!!! #{e.inspect}\n#{e.backtrace}"
      end
    end
  end
  
  def grab_blip_metadata
    # GET GET http://blip.tv/file/:id?skin=rss [channel/item/title]
  end
  
  def to_info
    {'id' => id,
     'url' => url,
     'provider' => provider,
     'title' => title,
     'duration' => duration,
     'playlist' => playlist,
     'position' => position}
  end
  
  def set_update_info
    @playlist_changed = playlist_changed?
    true
  end
  
  def notify_updates
    SUBSCRIPTIONS.send_message(channel_id, to_info.merge({'type' => 'playlist_video'}))
    @playlist_changed = false
    true
  end
  
  def notify_destroy
    SUBSCRIPTIONS.send_message(channel_id, {'type' => 'playlist_video_removed', 'id' => id})
    true
  end
end

dbconfig = YAML.load(File.read('config/database.yml'))
Time.zone = 'UTC'
ActiveRecord::Base.time_zone_aware_attributes = true
ActiveRecord::Base.default_timezone = :utc
ActiveRecord::Base.establish_connection dbconfig['development']

JSON.create_id = nil

# Big nasty shared subscriptions list

class SubscriberList
  def initialize
    @list = {}
  end
  
  def send_message(destination, message)
    if destination.respond_to?(:each)
      destination.each do |channel|
        send_message(channel, message)
      end
    else
      channel_id = if destination.class == Channel
        destination.id
      else
        destination
      end
    end
    
    return if @list[channel_id].nil?
    puts "SENDING MESSAGE TO: #{@list[channel_id].map(&:object_id).join(',')}"
    @list[channel_id].each do |subscriber|
      subscriber.send_message(message)
    end
  end
  
  def has_channel_id?(channel)
    @list.has_key?(channel)
  end
  
  def connection_in_channel_id?(connection, channel)
    @list[channel] && @list[channel].include?(connection)
  end
  
  def subscribe(connection, channel)
    permission_scope = (connection.current_user and (connection.current_user.id == channel.user_id)) ? ['admin'] : []
    @list[channel.id] ||= []
    @list[channel.id].each{|socket| socket.send_message({'type' => 'userjoined', 'user_id' => connection.user_id, 'user' => connection.user_name, 'scope' => permission_scope})}
    @list[channel.id] << connection
    @list[channel.id].each do |socket|
      connection.send_message({'type' => 'userjoined', 'user_id' => socket.user_id, 'user' => socket.user_name, 'scope' => (socket.current_user and (socket.current_user.id == channel.user_id)) ? ['admin'] : []})
    end
  end
  
  def unsubscribe(connection, channel=nil)
    if !channel.nil?
      @list[channel.id].delete(connection)
    else
      @list.each do |subscriber_channel, users|
        if users.include?(connection)
          users.delete(connection)
          users.each{|socket| socket.send_message({'type' => 'userleft', 'user_id' => connection.user_id})}
        end
      end
    end
  end
end

SUBSCRIPTIONS = SubscriberList.new

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
      puts "EXCEPTION: #{e.inspect}\n#{e.backtrace.join("\n")}"
    end
  end
  
  def user_id
    @current_user ? "user_#{@current_user.id}" : "anon_#{object_id}"
  end
  
  def user_name
    @current_user ? @current_user.name : @current_name
  end
  
  def current_user
    @current_user
  end
  
  def process_message(env, data)
    message = JSON.parse(data) rescue {}
    puts "#{user_id}: #{message.inspect}"
    now = Time.now.utc
    
    case message['type']
    when 'auth'
      user = User.find_by_auth_token(message['auth_token'])
      if user && user.auth_token?
        puts "OPEN user == #{user.inspect}"
        @current_user = user
        send_message({'type' => 'hello', 'nickname' => user_name, 'user_id' => user_id})
        @current_user.update_attribute(:auth_token, nil)
      else
        @current_name = message['nickname']||'Anonymous'
        send_message({'type' => 'hello', 'nickname' => user_name, 'user_id' => user_id})
      end
    when 'message'
      if SUBSCRIPTIONS.connection_in_channel_id?(self, message['channel_id'])
        SUBSCRIPTIONS.send_message(message['channel_id'], {
          'type' => 'message',
          'user_id' => user_id,
          'content' => message['content']
        })
      end
    when 'changename'
      new_name = (message['nickname']||'').strip
      if @current_user.nil? and !new_name.empty? and new_name != user_name
        @current_name = new_name
        SUBSCRIPTIONS.send_message(message['channel_id'], {'type' => 'changename',
                                                           'user' => user_name,
                                                           'user_id' => user_id})
      end
    when 'subscribe'
      channel = Channel.find_by_id(message['channel_id'])
      if channel
        puts "SUBSCRIBING TO CHANNEL #{channel.name}"
        SUBSCRIPTIONS.subscribe(self, channel)
        
        # Get current video
        if channel.current_video
          puts "VIDEO? #{channel.current_video.url} #{channel.current_video.provider}"
          send_message(channel.current_video.to_info.merge({
                        'type' => 'video',
                        'time' => channel.current_time,
                        'force' => true}))
        end
        
        # Get current playlist
        videos = channel.videos.order('position ASC')
        unless videos.empty?
          videos.each { |video| send_message(video.to_info.merge({'type' => 'playlist_video'})) }
        end
      end
    when 'unsubscribe'
      channel = Channel.find_by_id(message['channel_id'])
      SUBSCRIPTIONS.unsubscribe(self, channel) if channel
    when 'video'
      return if @current_user.nil?
      # Only the owner of the channel can set the video
      
      # TWO OPTIONS:
      # 1) Provide video id (in playlist)
      # 2) Provide video url (grabs metadata later)
      
      if SUBSCRIPTIONS.has_channel_id?(message['channel_id'])
        channel = Channel.find_by_id(message['channel_id'])
        if channel.user == @current_user
          if message['video_id']
            channel.play_item(message['video_id'])
          elsif message['url']
            channel.quickplay_video(Video.get_playback_info(message['url']))
          end
        end
      end
    when 'video_finished'
      return if @current_user.nil?
      # Only the owner of the channel can set the video
      if SUBSCRIPTIONS.has_channel_id?(message['channel_id'])
        channel = Channel.find_by_id(message['channel_id'])
        if channel.user == @current_user
          channel.next_video!
        end
      end
    when 'video_time'
      return if @current_user.nil?
      channel = Channel.find_by_id(message['channel_id'])
      if channel && SUBSCRIPTIONS.has_channel_id?(channel.id)
        if !message['time'].nil? and channel.user_id == @current_user.id
          # Adjust channel model time if delta is too large
          current_time = channel.current_time(now)
          if (current_time - message['time'] < -1.0) or (current_time - message['time'] > 1.0)
            puts "ADJUSTING CHANNEL TIME: #{message['time']} vs #{current_time} / #{channel.current_time(now)} #{current_time - message['time']}"
            channel.delta_start_time!(message['time'], now)
          end
        end
      end
    end
  end
  
  def on_close(env)
    puts "CLOSE #{user_id}"
    SUBSCRIPTIONS.unsubscribe(self)
  end
end

class App < Sinatra::Base
  set :public, File.dirname(__FILE__) + '/public'
  set :static, true

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
  
  # Force set a video
  post '/set_video' do
    login_required
    content_type :json
    channel = Channel.find_by_id(params[:channel_id])
    if channel
      if channel.user == current_user
        # Determine what we want to play
        video_info = if params[:video_id] && params[:provider]
          {:video_id => params[:video_id], :provider => params[:provider], :time => params[:time].to_i}
        elsif params[:url]
          Video.get_playback_info(params[:url])
        else
          {:video_id => '', :provider => nil}
        end
        
        if video_info[:video_id].nil? or video_info[:provider].empty?
          {:error => 'UnknownVideo'}
        else
          # Update channel video
          channel.set_current_video_from_info(video_info, params[:time].to_i, Time.now)
          channel.save
          current_time = channel.current_video.current_time
          
          # Tell everyone
          subscribers.each do |subscriber|
            subscriber.send_message({'type' => 'video',
                                     'provider' => channel.current_video.provider,
                                     'url' => channel.current_video.url,
                                     'time' => current_time,
                                     'force' => true})
          end
          {:video_id => channel.current_video.url, :provider => channel.current_video.provider, :time => current_time}
        end
      else
        {:error => 'InsufficientPermissions'}
      end
    else
      {:error => 'UnknownChannel'}
    end.to_json
  end
  
  # Set current video to playlist item
  put '/video' do
    login_required
    content_type :json
    channel = Channel.find_by_id(params[:channel_id])
    
    response_data = {}
    if channel and channel.user == current_user
      video = channel.videos.find_by_id(params[:id])
      if video
        channel.play_item(video)
        response_data = video.to_info
      end
    end
    
    response_data.to_json
  end
  
  # Add video to playlist
  post '/video' do
    login_required
    content_type :json
    channel = Channel.find_by_id(params[:channel_id])
    
    response_data = {}
    if channel and channel.user == current_user
      video = channel.add_video(Video.get_playback_info(params[:url]))
      response_data = video.to_info if video
    end
    
    response_data.to_json
  end
  
  # Remove video
  delete '/video' do
    login_required
    content_type :json
    channel = Channel.find_by_id(params[:channel_id])
    
    response_data = {}
    if channel and (channel.user == current_user)
      video = channel.videos.find_by_id(params[:id])
      if video
        if channel.current_video == video
          video.update_attributes({:playlist => false})
        else
          video.destroy
        end
      end
    end
    
    response_data.to_json
  end
  
  # Update channel info
  put '/channel' do
  end
  
  # Token for socket identification
  post '/auth/socket_token' do
    login_required
    current_user.generate_auth_token!
    content_type :json
    {:auth_token => current_user.auth_token}.to_json
  end
end


