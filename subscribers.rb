
# Big nasty shared subscriptions list

class SubscriberList
  def initialize
    @list = {}
  end
  
  def send_message(destination, type, message)
    real_message = (message||{}).merge(:t => type)
    if destination.respond_to?(:each)
      destination.each do |channel|
        send_message(channel, real_message)
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
    @list[channel] && @list[channel].include?(connection)
  end
  
  def user_in_channel_id?(user, channel)
    @list[channel] && @list[channel].map(&:current_user).include?(user)
  end
  
  def user_id_in_channel_id?(user_id, channel)
    @list[channel] && @list[channel].map(&:user_id).include?(user_id)
  end
  
  def subscribe(connection, channel)
    permission_scope = (connection.current_user and (connection.current_user.id == channel.user_id)) ? ['admin'] : []
    @list[channel.id] ||= []
    @list[channel.id].each{|socket| socket.send_message({'t' => 'userjoined', 'uid' => connection.user_id, 'user' => connection.user_name, 'scope' => permission_scope})}
    @list[channel.id] << connection
    @list[channel.id].each do |socket|
      connection.send_message({'t' => 'userjoined', 'uid' => socket.user_id, 'user' => socket.user_name, 'scope' => (socket.current_user and (socket.current_user.id == channel.user_id)) ? ['admin'] : []})
    end
  end
  
  def unsubscribe(connection, channel=nil)
    if !channel.nil?
      @list[channel.id].delete(connection)
    else
      @list.each do |subscriber_channel, users|
        if users.include?(connection)
          users.delete(connection)
          users.each{|socket| socket.send_message({'t' => 'userleft', 'uid' => connection.user_id})}
        end
      end
    end
  end
end
