require 'spec_helper'

BASE_VIDEO_INFO = 
    {'url' => 'H0MwvOJEBOM',
     'provider' => 'dummy',
     'title' => 'HOW 2 DRAW SANIC HEGEHOG',
     'duration' => 0,
     'playlist' => false,
     'position' => nil}

describe Channel do
  before(:each) do
    Video.delete_all
    Channel.delete_all
    User.delete_all
    Timecop.return
  end


  describe "an instance" do
    before do
      @channel = Channel.create!(:name => 'v4c')

      @video = Video.create!(:title => BASE_VIDEO_INFO['title'],
                            :url => BASE_VIDEO_INFO['url'],
                            :duration => 60,
                            :provider => BASE_VIDEO_INFO['provider'])
    end

    it "should calculate the correct current_time" do
      @channel.current_time.should == 0
      @video.update_attribute(:channel_id, @channel.id)

      @channel.play_item(@video)

      Timecop.freeze(@channel.start_time + 10.seconds) { @channel.current_time.should == 10 }
      Timecop.freeze(@channel.start_time + 30.seconds) { @channel.current_time.should == 30 }
    end

    it "should update the correct delta_start_time!" do
      @channel.current_time.should == 0
      @video.update_attribute(:channel_id, @channel.id)

      @channel.play_item(@video)

      start = @channel.start_time
      Timecop.freeze(start) do
        @channel.delta_start_time!(60)
        @channel.current_time.should == 60
        @channel.delta_start_time!(60, start + 60.seconds)
        @channel.current_time.should == 0
      end
    end

    it "should go to the correct next_video!" do
    end

    it "should play_item existing videos in the playlist, clearing the current non-playlist video" do
    end

    it "add_view method should add a new video on the end of the playlist" do
    end

    it "quickplay_video method should add and instantly play an new video, or update the existing non-playlist one" do
    end

    it "should notify SUBSCRIPTIONS of changes to the current video and time" do
    end
  end
end