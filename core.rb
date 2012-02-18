$stdout.sync = true
ENV["RACK_ENV"] ||= "development"

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
    'admin.js',
    'youtube.js',
    'blip.js',
    'chat.js',
  ]

  def current_user
    @current_user ||= User.find_by_id(session[:user_id]) if session[:user_id]
  end

  def login_required
    if current_user.nil?
      if request.xhr?
        status 401
      else
        redirect '/auth'
      end
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
    
    def get_channels
      @channels ||= Channel.all
    end

    def public_tabs
      get_channels.map do |channel|
        {:id => "chan_#{channel.id}".to_sym, :class => 'room', :name => channel.name, :href => channel.permalink||channel.id}
      end
    end

    def admin_tabs
      [{:id => :"admin", :class => 'admin', :name => 'Admin', :url => '/admin'},
        {:id => :"admin_users", :class => 'admin', :name => 'Users', :url => '/admin/users'},
          {:id => :"admin_bans", :class => 'admin', :name => 'Bans', :url => '/admin/bans'},
          {:id => :"admin_channels", :class => 'admin', :name => 'Channels', :url => '/admin/channels'}] + get_channels.map do |channel|
        {:id => :"chan_#{channel.id}", :class => 'room', :name => channel.name, :url => "/admin/channels/#{channel.permalink||channel.id}"}
      end
    end

    def set_tab(the_tab)
      puts "SET TAB: #{the_tab}<<"
      @current_tab = the_tab
    end

    def get_tabs(list)
      current = @current_tab
      send(list).map do |tab|
        "<li id=\"tab_#{tab[:id]}\" class=\"#{tab[:class]}\"><a href=\"#{tab[:url]}\" #{current == tab[:id] ? 'class="active"' : ''}>#{escape_html tab[:name]}</a></li>"
      end.join('')
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
  
  # Token for socket identification
  post '/auth/socket_token' do
    login_required
    current_user.generate_auth_token!
    content_type :json
    {:auth_token => current_user.auth_token}.to_json
  end
  
  # Admin panel
  
  get '/admin*' do
    login_required
    return status(401) if !current_user.admin
    
    if params[:splat].first =~ /\/?(.*)$/
      @subpath = $1[-1] == '/' ? $1[0...-1] : $1
    end
    erb :admin, :layout => :'admin_layout'
  end
  
  # Enumerate connections, videos, ban count, historical figures, etc
  get '/stats' do
    login_required
    return status(401) if !current_user.admin
  end
  
  get '/users' do
    login_required
    return status(401) if !current_user.admin
    
    content_type :json
    User.all.map(&:to_info).to_json
  end
  
  post '/users' do
    login_required
    return status(401) if !current_user.admin
    
    content_type :json
    
    user = User.new(JSON.parse(request.body.read))
    puts User.attr_accessible.inspect
    puts user.inspect
    if user.save
      status 201
      user.to_info(:admin => true).to_json
    else
      status 422
      {:error => 'InvalidAttributes', :errors => user.errors}.to_json
    end
  end
  
  get '/users/:id' do
    login_required
    return status(401) if !current_user.admin
    
    content_type :json
    
    user = User.find_by_id(params[:id])
    if user
      user.to_info(:admin => true).to_json
    else
      status 404
      {:error => 'NotFound'}.to_json
    end
  end
  
  put '/users/:id' do
    login_required
    return status(401) if !current_user.admin
    
    content_type :json
    jparams = JSON.parse(request.body.read)
    p jparams.inspect
    user = User.find_by_id(params[:id])
    if user
      if user.update_attributes(jparams)
        user.to_info(:admin => true).to_json
      else
        status 422
        {:error => 'InvalidAttributes'}.to_json
      end
    else
      status 404
      {:error => 'NotFound'}.to_json
    end
  end
  
  delete '/users/:id' do
    login_required
    return status(401) if !current_user.admin
    
    content_type :json
    
    user = User.find_by_id(params[:id])
    if user
      if user != current_user && User.all.count > 1
        ban.destroy
      else
        status 406
        {:error => 'EndOfWorld'}.to_json
      end
    else
      status 404
      {:error => 'NotFound'}.to_json
    end
  end
  
  get '/bans' do
    login_required
    return status(401) if !current_user.admin
    
    content_type :json
    Ban.all.map(&:to_info).to_json
  end
  
  get '/ban/:id' do
    login_required
    return status(401) if !current_user.admin
    
    content_type :json
    
    ban = Ban.find_by_id(params[:id])
    if ban
      ban.to_info(:admin => true).to_json
    else
      status 404
      {:error => 'NotFound'}.to_json
    end
  end
  
  put '/ban/:id' do
    login_required
    return status(401) if !current_user.admin
    
    content_type :json
    
    ban = Ban.find_by_id(params[:id])
    if ban
      if ban.update_attributes(params[:ban])
        ban.to_info(:admin => true).to_json
      else
        status 422
        {:error => 'InvalidAttributes'}.to_json
      end
    else
      status 404
      {:error => 'NotFound'}.to_json
    end
  end

  post '/bans' do
    login_required
    return status(401) if !current_user.admin

    content_type :json

    ban = Ban.new(JSON.parse(request.body.read))
    if ban.save
      status 201
      ban.to_info(:admin => true).to_json
    else
      status 422
      {:error => 'InvalidAttributes', :errors => ban.errors}.to_json
    end
  end
  
  delete '/ban/:id' do
    login_required
    return status(401) if !current_user.admin
    
    content_type :json
    
    ban = Ban.find_by_id(params[:id])
    if ban
      ban.destroy
    else
      status 404
      {:error => 'NotFound'}.to_json
    end
  end
  
  post '/channel' do
    login_required
    return status(401) if !current_user.admin
    
    content_type :json
    
    channel = Channel.new(params[:channel])
    if channel.save
      channel.to_info(:admin => true).to_json
    else
      status 422
      {:error => 'InvalidAttributes'}.to_json
    end
  end
  
  # Update channel info
  put '/channel' do
    login_required
    return status(401) if !current_user.admin
    
    content_type :json
    
    channel = Channel.find_by_id(params[:channel_id])
    
    if channel and channel.can_admin(current_user)
      if channel.update_attributes params[:channel]
        channel.to_info(:admin => true).to_json
      else
        status 422
        {:error => 'InvalidAttributes'}.to_json
      end
    else
      {:error => 'NotFound'}
    end
  end
end


# Init Environment

dbconfig = YAML.load(File.read('config/database.yml'))
#Time.zone = 'UTC'
ActiveRecord::Base.time_zone_aware_attributes = true
ActiveRecord::Base.default_timezone = :utc
ActiveRecord::Base.logger = Logger.new(STDOUT)

JSON.create_id = nil

%w{models subscribers websocket util}.each do |lib|
  require File.join(File.dirname(__FILE__), lib)
end

ActiveRecord::Base.establish_connection dbconfig[ENV['RACK_ENV']]

SUBSCRIPTIONS = SubscriberList.new

