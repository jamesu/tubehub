
class WebSocketApp < Rack::WebSocket::Application
  
  API_VERSION=1
  
  def ip_for(env)
    if addr = env['HTTP_X_FORWARDED_FOR']
      addr.split(',').last.strip
    else
      env['REMOTE_ADDR']
    end
  end
  
  def on_open(env)
    # We cant rely on cookies so wait for the auth message
  end
  
  def auth
    @auth || false
  end
  
  def auth=(value)
    @auth = value
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
  
  def current_channel_id
    @current_channel_id
  end
  
  def user_id
    @current_user ? "user_#{@current_user.id}" : "anon_#{object_id}"
  end
  
  def user_name
    @current_name
  end
  
  def user_name_trip
    "#{@current_name}#{@current_tripcode}"
  end
  
  def user_data
    {:id => user_id, :name => user_name, :tripcode => @current_tripcode, :anon => @current_user ? false : true }
  end
  
  def current_user
    @current_user
  end
  
  def scope_for(channel)
    if @scope_chan != channel
      @scope = nil
      @scope_chan = channel
    end
    
    if @scope.nil?
      if @current_user && @current_user.super_admin
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
  
  def process_message(env, data)
    message = JSON.parse(data) rescue {}
    now = Time.now.utc
    
    puts "MSG: #{message}"
    
    # Socket needs to be authenticated FIRST
    return if !auth && message['t'] != 'auth'
    
    case message['t']
    when 'auth'
      # Authenticate the session
      # This is so connections can be associated with names
      # Note that besides banning there isn't really much in the way of
      # user control.
      user = User.find_by_auth_token(message['auth_token'])
      ban = Ban.find_active_by_ip(ip_for(env))
      puts "AUTH REQUEST FROM #{ip_for(env)}"
      if ban
        # User was banned
        send_message({'t' => 'goaway', 'reason' => 'ban', 'comment' => ban.comment})
      elsif user && user.auth_token?
        # Admin / channel admin login
        @current_user = user
        @current_name, @current_tripcode = Tripcode.encode(user.nick)
        send_message({'t' => 'hello', 'user' => user_data, 'api' => API_VERSION})
        @current_user.update_attribute(:auth_token, nil)
        puts "OPEN[#{ip_for(env)}] #{user_id}"
        SUBSCRIPTIONS.register_connection(self)
        @auth = true
      else
        # Anonymous login
        @current_name, @current_tripcode = Tripcode.encode(message['name']||'Anonymous')
        unt = user_name_trip
        
        if !User.find_by_eval_nick(unt)
          send_message({'t' => 'hello', 'user' => user_data, 'api' => API_VERSION})
          puts "OPEN[#{ip_for(env)}] #{user_id}"
          SUBSCRIPTIONS.register_connection(self)
          @auth = true
        else
          # not allowed
          send_message({'t' => 'goaway', 'reason' => 'inuse'})
        end
      end
    when 'message'
      # Messages are broadcast to subscribers
      if SUBSCRIPTIONS.connection_in_channel_id?(self, message['channel_id'])
        SUBSCRIPTIONS.send_message(message['channel_id'], 'message', {
          'uid' => user_id,
          'content' => message['content']
        })
      end
    when 'usermod'
      # User wants to change their name
      new_name, new_tripcode = Tripcode.encode((message['name']||'').strip)
      if @current_user.nil? and !new_name.empty? and new_name != user_name
        @current_name = new_name
        @current_tripcode = new_tripcode
        SUBSCRIPTIONS.send_message(message['channel_id'], 'usermod', {'user' => user_data})
      end
    when 'subscribe'
      # Subscribe to channel
      puts "#{user_id} SUBSCRIBE #{message['channel_id']}"
      channel = Channel.find_by_id(message['channel_id'])
      if channel
        # Unsubscribe from previous
        if @current_channel_id
          puts "#{user_id} UNSUBSCRIBE EXISTING #{@current_channel_id}"
          SUBSCRIPTIONS.unsubscribe(self, @current_channel_id)
        end
        
        puts "SUBSCRIBING TO CHANNEL #{channel.name} (#{channel.current_video.try(:url)})"
        SUBSCRIPTIONS.subscribe(self, channel)
        @current_channel_id = channel.id
        
        # Get current video
        if channel.current_video
          #puts "VIDEO? #{channel.current_video.url} #{channel.current_video.provider}"
          send_message(channel.current_video.to_info.merge({
                        't' => 'video',
                        'time' => channel.current_time,
                        'force' => true}))
        end
        
        # Get current playlist
        videos = channel.videos.order('position ASC')
        unless videos.empty?
          videos.each do |video|
            info = video.to_info.merge({'t' => 'playlist_video'})
            send_message(info)
          end
        end
      else
        send_message({'t' => 'goaway', 'reason' => 'notfound'})
      end
    when 'unsubscribe'
      # Unsubscribe from channel
      puts "#{user_id} UNSUBSCRIBE #{message['channel_id']}"
      channel = Channel.find_by_id(message['channel_id'])
      SUBSCRIPTIONS.unsubscribe(self, channel) if channel
      @current_channel_id = nil
    when 'video'
      # Force the video
      # Note: Only channel admins or moderators can do this.
      
      puts "#{user_id} VIDEO #{message['channel_id']} #{message['video_id']} #{message['url']}"
      
      # TWO OPTIONS:
      # 1) Provide video id (in playlist)
      # 2) Provide video url (grabs metadata later)
      
      if SUBSCRIPTIONS.has_channel_id?(message['channel_id'])
        channel = Channel.find_by_id(message['channel_id'])
        if scope_for(channel) != ''
          if message['video_id']
            video = channel.videos.find_by_id(message['video_id'])
            channel.play_item(video) if video
          elsif message['url']
            channel.quickplay_video(Video.get_playback_info(message['url']))
          end
        end
      end
    
    # TODO: 
    when 'video_finished'
      # Advance to next video
      # Note: Only channel admins or moderators can do this.
      
      # Only the owner of the channel can set the video
      puts "#{user_id} VIDEO FINISHED #{message['channel_id']}"
      
      if SUBSCRIPTIONS.has_channel_id?(message['channel_id'])
        channel = Channel.find_by_id(message['channel_id'])
        if scope_for(channel) != ''
          channel.next_video!
        end
      end
    when 'video_time'
      # Set video time
      # Note: Only channel admins or moderators can do this.
      
      channel = Channel.find_by_id(message['channel_id'])
      if channel && SUBSCRIPTIONS.has_channel_id?(channel.id)
        if !message['time'].nil? and scope_for(channel) != ''
          # Adjust channel model time if delta is too large
          current_time = channel.current_time(now)
          if (current_time - message['time'] < -1.0) or (current_time - message['time'] > 1.0)
            #puts "ADJUSTING CHANNEL TIME: #{message['time']} vs #{current_time} / #{channel.current_time(now)} #{current_time - message['time']}"
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
