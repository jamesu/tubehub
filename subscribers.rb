
# Big nasty shared subscriptions list

class SubscriberList
  def initialize
    @list = {}
    @connections = []
  end
  
  def reset
    @list = {}
    @connections = []
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
  
  def register_connection(connection)
    @connections.push(connection)
  end
  
  def subscribe(connection, channel)
    permission_scope = connection.scope_for(channel)
    @list[channel.id] ||= []
    @list[channel.id].each{|socket| socket.send_message({'t' => 'userjoined', 'user' => connection.user_data, 'scope' => permission_scope})}
    @list[channel.id] << connection
    @list[channel.id].each do |socket|
      connection.send_message({'t' => 'userjoined', 'user' => socket.user_data, 'scope' => socket.scope_for(channel)})
    end
  end
  
  def unsubscribe(connection, channel=nil)
    chan = channel.class == Channel ? channel.id : channel
    if !channel.nil?
      @list[chan].delete(connection)
      @list[chan].each{|socket| socket.send_message({'t' => 'userleft', 'user' => {:id => connection.user_id}})}
      @connections.delete(connection)
    else
      @list.each do |subscriber_channel, users|
        if users.include?(connection)
          users.delete(connection)
          users.each{|socket| socket.send_message({'t' => 'userleft', 'user' => {:id => connection.user_id}})}
        end
      end
    end
  end
end
