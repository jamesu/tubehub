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

        #puts "VIDEO #{url}: TITLE=#{title}, DURATION=#{duration}"
        unless title.nil? and duration.nil?
          record.title = title
          record.duration = duration
          record.save!
        end
      rescue Object => e
        #puts "VIDEO #{url}: ERROR GETTING METADATA!!! #{e.inspect}\n#{e.backtrace}"
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
