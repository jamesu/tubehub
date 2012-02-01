$stdout.sync = true
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

dbconfig = YAML.load(File.read('config/database.yml'))
#Time.zone = 'UTC'
ActiveRecord::Base.time_zone_aware_attributes = true
ActiveRecord::Base.default_timezone = :utc

JSON.create_id = nil

%w{models subscribers websocket util}.each do |lib|
  require File.join(File.dirname(__FILE__), lib)
end

ActiveRecord::Base.establish_connection dbconfig['development']

SUBSCRIPTIONS = SubscriberList.new

class App < Sinatra::Base
  set :public_folder, File.dirname(__FILE__) + '/public'
  set :static, true
  set :logging, true
  
  JS_FILES = [
    'support/jquery.min.js',
    'support/swfobject.js',
    'support/web_socket.js',
    'support/json2.js',
    'support/underscore-min.js',
    'support/backbone-min.js',
    'app.js',
    'youtube.js',
    'blip.js',
    'chat.js',
  ]

  def current_user
    @current_user ||= User.find_by_id(session[:user_id]) if session[:user_id]
  end

  def login_required
    if current_user.nil?
      redirect '/auth'
      halt
    end
  end
  
  def render_javascript(files)
    data = files.map{|f|File.read "#{File.dirname(__FILE__)}/javascripts/#{f}"}
    #Uglifier.compile(data.join(';'), {:squeeze => false})
    data
  end
  
  helpers do
    include Rack::Utils
    alias_method :h, :escape_html
  
    def partial(page, options={})
      erb page, options.merge!(:layout => false)
    end
    
    def link_to(name, href, options={})
      opts = options.keys.map { |key| "#{key}=\"#{options[key]}\"" }.join(' ')
      "<a href=\"#{escape_html(href)}\" #{opts}>#{name}</a>"
    end
  end

  get '/' do
    @channels = Channel.all
    
    erb :channel_index
  end
  
  get '/r/:id' do
    # Display the first channel for now
    @channel = Channel.find_by_id(params[:id])
    if @channel.nil?
      status 404
      halt
    else
      erb :channel
    end
  end
  
  get '/all.js' do
    content_type 'application/javascript'
    render_javascript JS_FILES
  end
  
  # Login

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
      if channel.can_be_moderated_by(current_user)
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
    
    puts "PUT VIDEO"
    response_data = {}
    if channel and channel.can_be_moderated_by(current_user)
      puts "ERRR FIND #{params[:id]}<<  #{params.keys.join(',')}"
      video = channel.videos.find_by_id(params[:id])
      if video
        puts "FOUND VIDEO, PLAYING"
        channel.play_item(video)
        response_data = video.to_info
      end
    end
    
    response_data.to_json
  end
  
  # Add video to playlist
  post '/video' do
    content_type :json
    channel = Channel.find_by_id(params[:channel_id])
    
    puts "POST VIDEO"
    response_data = {}
    if channel# and channel.video_can_be_added_by(current_user)
      puts "ALRIGHT...."
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
    if channel and channel.can_be_moderated_by(current_user)
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
    login_required
    content_type :json
    channel = Channel.find_by_id(params[:channel_id])
    
    response_data = {}
    if channel and channel.can_admin(current_user)
      if channel.update_attributes params[:channel]
        
      else
      end
    end
    
    response_data.to_json
  end
  
  # Token for socket identification
  post '/auth/socket_token' do
    login_required
    current_user.generate_auth_token!
    content_type :json
    {:auth_token => current_user.auth_token}.to_json
  end
end


