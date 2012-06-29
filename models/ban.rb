class Ban < ActiveRecord::Base
  attr_accessible :ip, :created_at, :ended_at, :comment, :banned_by, :banned_by_ip, :duration
  
  after_save :check_connections
  
  def duration
    ended_at - (created_at||Time.now.utc)
  end
  
  def duration=(value)
    vi = value.to_i
    if vi < 0
      self[:ended_at] = nil
    else
      self[:ended_at] = Time.now.utc + vi
    end
  end
  
  def check_connections
    SUBSCRIPTIONS.kick_ip(ip)
  end
  
  def self.find_active_by_ip(ip)
    bans = Ban.order('ended_at').where(:ip => ip)
    bans.each do |ban|
      if ban.nil? or (!ban.ended_at.nil? and ban.ended_at < Time.now.utc)
        nil
      else
        return ban
      end
    end
    nil
  end
  
  def to_info(options={})
    base = {'id' => id,
     'ip' => ip,
     'created_at' => created_at.to_i,
     'ended_at' => ended_at.to_i,
     'comment' => comment}
    
    if options[:admin]
     base['banned_by'] = banned_by
     base['banned_by_ip'] = banned_by_ip
    end
    
    base
  end
end
