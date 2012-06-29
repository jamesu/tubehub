class Channel < ActiveRecord::Base
  belongs_to :user
  belongs_to :current_video, :class_name => 'Video'
  has_and_belongs_to_many :admin_channels, :class_name => 'User', :join_table => 'channel_admins'
  has_many :moderators
  has_many :videos, :order => 'position ASC, id ASC'
  
  before_update :set_update_info
  after_update :notify_updates
  
  attr_accessible :name, :permalink, :banner, :footer, :moderator_list, :skip_limit, :connection_limit, :video_limit, :locked
  
  validates_presence_of :name
  validates_presence_of :permalink
  validates_uniqueness_of :permalink
  
  before_validation :update_fields

  def self.find_by_id_or_permalink(value)
    where(['id = ? OR permalink = ?', value, value]).first
  end
  
  def update_fields
    if self[:permalink].nil? or self[:permalink].empty?
      self[:permalink] = (self[:name]||'').downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^\\-+|\\-+$/, '')
    end
  end
  
  def moderator_list
    @moderator_list ||= moderators.map(&:name).join("\n")
    @moderator_list
  end
  
  def moderator_list=(value)
    @moderator_list = nil

    old_list = moderators.to_a
    current_list = old_list
    new_list = value.split("\n").map(&:strip)
    
    to_add = []
    to_delete = []
    
    # Add to to_add
    new_list.each do |l|
      idx = old_list.index{|m|m.name == l}
      to_add << l if idx.nil?
    end
    
    # Add to to_delete
    old_list.each do |l|
      idx = new_list.index{|m|m == l.name}
      to_delete << l if idx.nil?
    end
    
    to_add.each do |mod|
      moderators.build(:name => mod)
    end
    moderators.delete(to_delete)
    
    moderators
  end
  
  # Update to new time (e.g. when user has manipulated slider)
  def delta_start_time!(new_time, from=Time.now.utc)
    self.start_time = from - new_time
    save
  end
  
  # Current time based upon channel start time
  def current_time(from=Time.now.utc)
    start_time ? from - start_time : 0
  end
  
  def set_next_video
    # Current video in playlist?
    video_idx = videos(true).index(current_video)
    last_video = current_video
    
    ret = if video_idx.nil? and !videos.empty?
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
    
    # Destroy old non-playlist video
    if !last_video.nil? and current_video != last_video and last_video.playlist == false
      last_video.destroy
    end
    
    ret
  end
  
  # Skip video if count exceeds limits
  def skip_video!(vote_count, user_count)
    return if skip_limit.nil?
    if vote_count >= (user_count * (skip_limit / 100.0))
      next_video!
    end
  end
  
  # Go to next video in playlist
  def next_video!
    set_next_video
    save if @video_changed
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
                        :playlist => true,
                        :added_by => options[:added_by],
                        :added_by_ip => options[:added_by_ip]}
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
    video.attributes = {:url => video_info[:video_id], :provider => video_info[:provider], :added_by => options[:added_by], :added_by_ip => options[:added_by_ip]}
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
    @fields_changed = changes
    true
  end
  
  def notify_updates
    if @video_changed
      SUBSCRIPTIONS.send_message(id, 'video', current_video.to_info.merge({'time' => current_time, 'force' => @force_video||false}))
      SUBSCRIPTIONS.reset_skips(id)
    elsif @time_changed
      SUBSCRIPTIONS.send_message(id, 'video_time', {'time' => current_time})
    elsif @fields_changed
      # Notify when fields have changed
      allowed_fields = ['name', 'permalink', 'banner', 'footer', 'skip_limit', 'connection_limit', 'locked', 'video_limit']
      @changed_keys = @fields_changed.keys & allowed_fields
      
      unless @changed_keys.empty?
        msg = {'id' => id}
        @changed_keys.each{|k| msg[k] = @fields_changed[k][1]}
        SUBSCRIPTIONS.send_message(id, 'chanmod', msg)
      end
    end
    
    @video_changed = @time_changed = false
    @changed_keys = nil
    SUBSCRIPTIONS.refresh_channels
    true
  end
  
  # Permissions
  
  def can_be_moderated_by(current_user)
    current_user.id == user_id
  end
  
  def can_admin(current_user)
    current_user.admin || admin_channels.include?(current_user)
  end
  
  def video_can_be_added_by(current_user)
    SUBSCRIPTIONS.user_id_in_channel_id?(current_user.id, id)
  end
  
  
  # Serialization
  
  def to_info(options={})
    base = {
      :id => id,
      :name => name,
      :permalink => permalink,
      :created_at => created_at.to_i,
      :updated_at => updated_at.to_i,
      :start_time => start_time.to_i,
      :current_video => current_video ? current_video.to_info(options) : nil,
      :skip_limit => skip_limit,
      :connection_limit => connection_limit,
      :locked => locked,
      :video_limit => video_limit
    }
    
    if options[:admin]
      base[:admin_user_ids] = admin_channels.map(&:id)
      base[:moderators] = moderators.map(&:name)
    end
    
    if options[:full] or options[:admin]
      base[:banner] = banner
      base[:footer] = footer
    end
    
    base
  end
  
  def stats_enumerate
    {
      :id => id,
      :permalink => permalink,
      :name => name,
      :videos => videos.map(&:to_info),
      :current_video_id => current_video_id,
      :start_time => start_time.to_i
    }
  end  
end
