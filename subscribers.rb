
# Big nasty shared subscriptions list

class SubscriberList
  def initialize(opts={})
    @list = {}
    @metadata = {}
    @connections = []
    @logger = Logger.new(opts[:log]||STDOUT)
  end
  
  def logger
    @logger
  end
  
  def reset
    @list = {}
    @metadata = {}
    @connections = []
    stop_timer
  end
  
  # Refresh user data (e.g. after updating a user)
  def refresh_users
    @connections.each{|c| c.current_user.reload if c.current_user}
  end
  
  def refresh_channels
    @metadata.keys.each{|k| @metadata[k] = Channel.find_by_id(@metadata[k].id) }
  end
  
  def channel_metadata(channel_id)
    @metadata[channel_id.to_i]
  end
  
  def reset_skips(channel_id)
    (@list[channel_id]||[]).each{|s| s.skip=false}
  end
  
  # Start a background update timer to advance leaderless channels
  def start_timer
    stop_timer
    @timer = EventMachine::PeriodicTimer.new(1) do
      #puts "TIMER PROCESS ITERATE"
      do_timer
    end
  end
  
  def do_timer
    @metadata.each do |channel_id, channel|
      # Ignore channels with leaders
      next if @list[channel_id].index{|s|s.leader} != nil
      
      # Advance to next video if we've run out of time + gap
      # Ignore current videos without time
      if channel.current_video.nil? or (!channel.current_video.duration.nil? && (channel.current_time >= (channel.current_video.duration+2)))
        #puts "ADVANCE VIDEO ON CHANNEL #{channel.permalink}"
        channel.next_video!
      end
    end
  end
  
  def stop_timer
    @timer.cancel if @timer
  end
  
  def stats_enumerate
    {
      :connections => @connections.length,
      :channels => {}.tap {|l| l.each{|k,v| l[k] = v.length } }
    }
  end
  
  def send_message(destination, type, message)
    real_message = type.nil? ? message : (message||{}).merge('t' => type)
    if destination.respond_to?(:each)
      destination.each do |channel|
        send_message(channel, nil, real_message)
      end
    else
      channel_id = if destination.class == Channel
        destination.id
      else
        destination
      end
      
      return if @list[channel_id].nil?
      #puts "SENDING MESSAGE TO: #{@list[channel_id].map(&:object_id).join(',')}"
      @list[channel_id].each do |subscriber|
        subscriber.send_message(real_message)
      end
    end
  end
  
  def has_channel_id?(channel)
    @list.has_key?(channel)
  end
  
  def connection_in_channel_id?(connection, channel)
    @list[channel] && @list[channel].include?(connection) ? true : false
  end
  
  def user_in_channel_id?(user, channel)
    @list[channel] && @list[channel].map(&:current_user).include?(user) ? true : false
  end
  
  def user_id_in_channel_id?(user_id, channel)
    @list[channel] && @list[channel].map(&:user_id).include?(user_id) ? true : false
  end
  
  def user_name_trip_connected?(user_trip)
    @connections.index{|c| c.user_name_trip == user_trip} != nil
  end
  
  def user_count_in_channel_id(channel_id)
    @list[channel_id] ? @list[channel_id].length : 0
  end
  
  def skip_count_in_channel_id(channel_id)
    (@list[channel_id]||[]).inject(0){|sum,i| sum+(i.skip||0)}
  end
  
  def kick(user_id)
    con = @connections.find{|c|c.user_id == user_id}
    unless con.nil?
      con.close_websocket unless con.current_user && con.current_user.admin
    end
  end
  
  def ban(user_id)
    con = @connections.find{|c|c.user_id == user_id}
    unless con.nil?
      return if con.current_user && con.current_user.admin
      
      addresses = con.addresses
      addresses.each do |addr|
        #next if addr == '127.0.0.1'
        Ban.create!(:ip => addr,
                    :ended_at => Time.now.utc + 1.day,
                    :banned_by => con.user_name_trip,
                    :banned_by_ip => con.addresses.join(','),
                    :comment => "1 day ban")
      end
    end
  end
  
  def kick_ip(ip)
    cons = @connections.reject{|c|!c.addresses.include?(ip)}
    cons.each do |con|
      con.close_websocket unless con.current_user && con.current_user.admin
    end
  end
  
  def set_channel_leader(channel_id, leader_id)
    (@list[channel_id]||[]).each do |socket|
      old_leader = socket.leader
      if socket.user_id == leader_id
        socket.leader = true
      else
        socket.leader = false
      end
      
      if socket.leader == true && old_leader != socket.leader
        send_message(channel_id, 'usermod', {:user => socket.user_data})
      end
    end
  end
  
  def register_connection(connection)
    @connections.push(connection)
  end
  
  def subscribe(connection, channel)
    permission_scope = connection.scope_for(channel)
    num_skips = 0
    connection.leader = false
    @list[channel.id] ||= []
    @metadata[channel.id] ||= channel
    @list[channel.id].each{|socket| socket.send_message({'t' => 'userjoined', 'user' => connection.user_data, 'scope' => permission_scope})}
    @list[channel.id] << connection
    @list[channel.id].each do |socket|
      connection.send_message({'t' => 'userjoined', 'user' => socket.user_data, 'scope' => socket.scope_for(channel)})
      num_skips += 1 if socket.skip
    end
    
    # Notify skip count
    if num_skips > 0
      connection.send_message({'t' => 'skip', 'count' => num_skips})
    end
  end
  
  def unsubscribe(connection, channel=nil)
    chan = channel.class == Channel ? channel.id : channel
    if !channel.nil?
      @list[chan].delete(connection)
      skip_count = skip_count_in_channel_id(chan)
      @list[chan].each do |socket|
        socket.send_message({'t' => 'userleft', 'user' => {:id => connection.user_id}})
        # Notify skip count
        socket.send_message({'t' => 'skip', 'count' => skip_count}) if connection.skip
      end
    else
      @list.each do |subscriber_channel, users|
        if users.include?(connection)
          users.delete(connection)
          skip_count = skip_count_in_channel_id(subscriber_channel)
          users.each do |socket|
            socket.send_message({'t' => 'userleft', 'user' => {:id => connection.user_id}})
            socket.send_message({'t' => 'skip', 'count' => skip_count}) if connection.skip
          end
        end
      end
      @connections.delete(connection)
    end
  end
end
