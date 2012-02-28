require 'spec_helper'

describe Video do
  before(:each) do
    Video.delete_all
    Channel.delete_all
    User.delete_all
  end

  describe "get_playback_info" do
    it "should process blip.tv links" do
      Video.get_playback_info("http://blip.tv/play/AYKYuUQC.html").should == {:video_id => 'AYKYuUQC', :time => 0, :provider => 'blip'}
      Video.get_playback_info("http://blip.tv/play/AYKYuUQC.html/wtf").should == {:video_id => 'AYKYuUQC', :time => 0, :provider => 'blip'}
      Video.get_playback_info("http://blip.tv/play/AYKYuUQC").should == {:video_id => 'AYKYuUQC', :time => 0, :provider => 'blip'}
    end

    it "should process youtube links" do
      Video.get_playback_info("http://www.youtube.com/watch?v=ko4k_Ya4n6w&list=AAB4zxTWQN5g-Mu5F0meR1WA&index=2&feature=plpp_video").should == {:video_id => 'ko4k_Ya4n6w', :time => 0, :provider => 'youtube'}
      Video.get_playback_info("http://www.youtube.com/watch?list=AAB4zxTWQN5g-Mu5F0meR1WA&feature=player_detailpage&v=8WZr6fvtEgk#t=53s").should == {:video_id => '8WZr6fvtEgk', :time => 53, :provider => 'youtube'}
      Video.get_playback_info("http://www.youtube.com/watch?feature=player_detailpage&v=o2ptkJxmEEo#t=123s").should == {:video_id => 'o2ptkJxmEEo', :time => 123, :provider => 'youtube'}
      Video.get_playback_info("http://www.youtube.com/watch?feature=player_detailpage&v=o2ptkJxmEEo#t=1h60m123s").should == {:video_id => 'o2ptkJxmEEo', :time => 7323, :provider => 'youtube'}
      Video.get_playback_info("http://www.youtube.com/watch?feature=player_detailpage&v=o2ptkJxmEEo#t=").should == {:video_id => 'o2ptkJxmEEo', :time => 0, :provider => 'youtube'}
      Video.get_playback_info("http://www.youtube.com/watch?feature=player_detailpage&v=#t=").should == {:video_id => nil, :time => 0, :provider => 'youtube'}
    end

    it "should not process unknown links" do
      Video.get_playback_info("http://www.notube.com/watch?feature=player_detailpage&v=o2ptkJxmEEo#t=123s").should == {:video_id => nil, :time => 0, :provider => nil}
    end
  end

  describe "parse_yttimestamp" do
    it "should parse timestamps" do
      Video.parse_yttimestamp("2h").should == 7200
      Video.parse_yttimestamp("3m").should == 180
      Video.parse_yttimestamp("1s").should == 1
      Video.parse_yttimestamp("s1").should == 0
      Video.parse_yttimestamp("s1").should == 0
      Video.parse_yttimestamp("t=1m").should == 60
      Video.parse_yttimestamp("2h3m1s").should == 7381
    end
  end
  
  describe "an instance" do
    it "should notify SUBSCRIPTIONS of creation" do
      channel = Channel.create!(:name => 'v4c')
      video = Video.new(:channel_id => channel.id,
                            :title => BASE_VIDEO_INFO['title'],
                            :url => BASE_VIDEO_INFO['url'],
                            :provider => BASE_VIDEO_INFO['provider'],
                            :added_by => BASE_VIDEO_INFO['added_by'])
      
      SUBSCRIPTIONS.should_receive(:send_message) do |cid, ct, info|
        cid.should == channel.id
        ct.should == 'playlist_video'
        info.should == video.to_info
      end
      
      video.id = 1
      video.save
    end
    
    it "should notify SUBSCRIPTIONS of updates" do
      channel = Channel.create!(:name => 'v4c')
      video = Video.new(:channel_id => channel.id,
                            :title => BASE_VIDEO_INFO['title'],
                            :url => BASE_VIDEO_INFO['url'],
                            :provider => BASE_VIDEO_INFO['provider'],
                            :added_by => BASE_VIDEO_INFO['added_by'])
      video.id = 1
      video.save
      
      SUBSCRIPTIONS.should_receive(:send_message) do |cid, ct, info|
        cid.should == channel.id
        ct.should == 'playlist_video'
        info.should == video.to_info
      end

      video.title = 'Modified Name'
      video.save!
    end

    it "should notify SUBSCRIPTIONS of destruction" do
      channel = Channel.create!(:name => 'v4c')
      video = Video.new(:channel_id => channel.id,
                            :title => BASE_VIDEO_INFO['title'],
                            :url => BASE_VIDEO_INFO['url'],
                            :provider => BASE_VIDEO_INFO['provider'],
                            :added_by => BASE_VIDEO_INFO['added_by'])
      video.id = 1
      video.save

      SUBSCRIPTIONS.should_receive(:send_message).with(channel.id, 'playlist_video_removed', {'id' => video.id})

      video.destroy
    end
  end
end

