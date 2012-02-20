
class User < ActiveRecord::Base
  before_validation :update_tokens
  attr_accessor :password, :password_confirm
  attr_accessor :last_set_time
  
  has_and_belongs_to_many :admin_channels, :class_name => 'Channel', :join_table => 'channel_admins'
  
  attr_accessible :name, :nick, :password, :password_confirm
  
  validates_presence_of :name
  validates_presence_of :nick
  validates_uniqueness_of :name
  validates_uniqueness_of :nick
  validates_presence_of :password, :on => :create
  
  validate :check_password
  before_save :generate_eval_nick
  
  def check_password
    if @password_confirm != @password
      errors.add(:password_confirm, 'Password needs to be confirmed')
    end
  end
  
  def update_tokens
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
  
  def generate_auth_token
    tnow = Time.now()
    sec = tnow.tv_usec
    usec = tnow.tv_usec % 0x100000
    rval = rand()
    roffs = rand(25)
    self[:auth_token] = Digest::SHA1.hexdigest(Digest::SHA1.hexdigest(sprintf("%s%08x%05x%.8f", rand(32767), sec, usec, rval))[roffs..roffs+12])
  end
  
  def generate_auth_token!
    generate_auth_token
    save!
  end
  
  def generate_eval_nick
    self[:eval_nick] = Tripcode.encode(nick).join('') if nick_changed? or new_record?
  end
  
  def to_info(options={})
    base = {
      :id => id,
      :name => name,
      :nick => nick
    }
    
    if options[:admin]
      base.merge!({
        :created_at => created_at.to_i,
        :updated_at => updated_at.to_i,
        :admin => admin
      })
    end
    
    base
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
  has_and_belongs_to_many :admin_channels, :class_name => 'User', :join_table => 'channel_admins'
  has_many :moderators
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
    video_idx = videos.index(current_video)
    if video_idx.nil? and !videos.empty?
      self.current_video = videos.first
      self.start_time = Time.now.utc
      @video_changed = true
      @force_video = true
      save
    elsif !video_idx.nil?
      video_idx += 1
      video_idx = 0 if video_idx == videos.length
      self.current_video = videos[video_idx]
      self.start_time = Time.now.utc
      @video_changed = true
      @force_video = true
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
  def add_video(video_info, from=Time.now.utc, options={})
    if video_info[:provider] == nil || video_info[:video_id].nil?
      return nil
    end
    
    video = videos.build
    
    # Set attributes now
    video.attributes = {:url => video_info[:video_id],
                        :provider => video_info[:provider],
                        :position => videos.count,
                        :playlist => true}
    video.save
    
    video.grab_metadata unless options[:no_metadata]
    video
  end
  
  # Plays video info, grabs metadata later
  def quickplay_video(video_info, from=Time.now.utc, options={})
    video = if current_video and !current_video.playlist
      @video_changed = video_info[:video_id] != current_video.url
      current_video
    else
      videos.build({:playlist => false})
    end
    
    # Set attributes now
    video.attributes = {:url => video_info[:video_id], :provider => video_info[:provider]}
    video_saved = video.save
    
    video.grab_metadata unless options[:no_metadata]
    
    new_time = video_info[:time]||0
    self.current_video = video if video_saved
    self.start_time = from - new_time
    save
  end
  
  def set_update_info
    @video_changed ||= current_video_id_changed?
    @time_changed ||= start_time_changed?
    true
  end
  
  def notify_updates
    if @video_changed
      SUBSCRIPTIONS.send_message(id, 'video', current_video.to_info.merge({'time' => current_time, 'force' => @force_video||false}))
    elsif @time_changed
      SUBSCRIPTIONS.send_message(id, 'video_time', {'time' => current_time})
    end
    @video_changed = @time_changed = false
    true
  end
  
  # Permissions
  
  def can_be_moderated_by(current_user)
    current_user.id == user_id
  end
  
  def can_admin(current_user)
    current_user.id == user_id
  end
  
  def video_can_be_added_by(current_user)
    SUBSCRIPTIONS.user_id_in_channel_id?(current_user.id, id)
  end
  
  
  # Serialization
  
  def to_info(options={})
    base = {
      :id => id,
      :user => user.try(:to_info),
      :name => name,
      :created_at => created_at.to_i,
      :updated_at => updated_at.to_i,
      :start_time => start_time.to_i,
      :current_video => current_video.to_info(options)
    }
    
    if options[:full]
      options[:header] = header
      options[:fooer] = footer
    end
    
    base
  end
  
end

class Video < ActiveRecord::Base
  belongs_to :channel
  belongs_to :user
  
  before_update :set_update_info
  after_save :notify_updates
  after_destroy :notify_destroy
  
  BLIP_MATCH = /\/play\/([^\.\/+]*)/
  def self.get_playback_info(url)
    location = URI.parse(url) rescue nil
    host = location ? location.host : ''
    query = location ? CGI.parse(location.query) : {} rescue {}
    
    provider, video_id, video_time = case host
    when 'blip.tv'
      match = location.path.match(BLIP_MATCH)
      match ? ['blip', match[1], 0] : ['blip', nil, 0]
    when 'youtube.com', 'www.youtube.com'
      time = location.fragment ? parse_yttimestamp(location.fragment) : 0
      ['youtube', query['v'] ? query['v'][0].to_s : nil, time]
    else
      [nil, '', 0]
    end
    
    {:video_id => (video_id.nil? || video_id.empty?) ? nil : video_id, :time => video_time, :provider => provider}
  end

  YT_TIMESTAMP_MATCH=/(?:t=)?([0-9]+)(h|m|s)/i
  def self.parse_yttimestamp(stamp)
    total=0
    stamp.scan(YT_TIMESTAMP_MATCH) do |u,t|
      case t
      when 'h'
        total += u.to_i * 3600
      when 'm'
        total += u.to_i * 60
      when 's'
        total += u.to_i
      end
    end
    total
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
  
  def to_info(options={})
    base = {'id' => id,
     'url' => url,
     'provider' => provider,
     'title' => title,
     'duration' => duration,
     'playlist' => playlist,
     'position' => position,
     'added_by' => added_by}
    base['added_by_ip'] = added_by_ip if options[:mod]
    base
  end
  
  def set_update_info
    @playlist_changed = playlist_changed?
    true
  end
  
  def notify_updates
    SUBSCRIPTIONS.send_message(channel_id, 'playlist_video', to_info)
    @playlist_changed = false
    true
  end
  
  def notify_destroy
    SUBSCRIPTIONS.send_message(channel_id, 'playlist_video_removed', {'id' => id})
    true
  end
end

class Moderator < ActiveRecord::Base
  belongs_to :channel
  
  def to_info(options={})
    {:name => name}
  end
end

class Ban < ActiveRecord::Base
  attr_accessible :ip, :created_at, :ended_at, :comment, :banned_by, :banned_by_ip
  
  def duration
    ended_at - (created_at||Time.now.utc)
  end
  
  def duration=(value)
    self[:ended_at] = Time.now.utc + value
  end 
  
  def self.find_active_by_ip(ip)
    ban = Ban.order('ended_at').where(:ip => ip).last
    if ban.nil? or ban.ended_at.nil? or ban.ended_at < Time.now.utc
      nil
    else
      ban
    end
  end
  
  def to_info(options={})
    {'id' => id,
     'ip' => ip,
     'created_at' => created_at.to_i,
     'ended_at' => ended_at.to_i,
     'comment' => comment,
     'banned_by' => banned_by,
     'banned_by_ip' => banned_by_ip}
  end
end


