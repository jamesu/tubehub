
class WebSocketApp < Rack::WebSocket::Application
  
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
    now = Time.now.utc
    
    case message['t']
    when 'auth'
      user = User.find_by_auth_token(message['auth_token'])
      ban = Ban.find_active_by_ip(ip_for(env))
      puts "AUTH REQUEST FROM #{ip_for(env)}"
      if ban
        send_message({'t' => 'goaway', 'reason' => 'banned', 'comment' => ban.comment})
      elsif user && user.auth_token?
        @current_user = user
        send_message({'t' => 'hello', 'nickname' => user_name, 'uid' => user_id})
        @current_user.update_attribute(:auth_token, nil)
        puts "OPEN[#{ip_for(env)}] #{user_id}"
      else
        @current_name = message['nickname']||'Anonymous'
        send_message({'t' => 'hello', 'nickname' => user_name, 'uid' => user_id})
        puts "OPEN[#{ip_for(env)}] #{user_id}"
      end
    when 'message'
      if SUBSCRIPTIONS.connection_in_channel_id?(self, message['channel_id'])
        SUBSCRIPTIONS.send_message(message['channel_id'], 'message', {
          'uid' => user_id,
          'content' => message['content']
        })
      end
    when 'changename'
      new_name = (message['nickname']||'').strip
      if @current_user.nil? and !new_name.empty? and new_name != user_name
        @current_name = new_name
        SUBSCRIPTIONS.send_message(message['channel_id'], 'changename', {'user' => user_name,
                                                           'uid' => user_id})
      end
    when 'subscribe'
      puts "#{user_id} SUBSCRIBE #{message['channel_id']}"
      channel = Channel.find_by_id(message['channel_id'])
      if channel
        #puts "SUBSCRIBING TO CHANNEL #{channel.name}"
        SUBSCRIPTIONS.subscribe(self, channel)
        
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
          videos.each { |video| send_message(video.to_info.merge({'t' => 'playlist_video'})) }
        end
      end
    when 'unsubscribe'
        puts "#{user_id} UNSUBSCRIBE #{message['channel_id']}"
      channel = Channel.find_by_id(message['channel_id'])
      SUBSCRIPTIONS.unsubscribe(self, channel) if channel
    when 'video'
      return if @current_user.nil?
      puts "#{user_id} VIDEO #{message['channel_id']} #{message['video_id']} #{message['url']}"
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
      puts "#{user_id} VIDEO FINISHED #{message['channel_id']}"
      
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
