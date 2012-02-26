require 'spec_helper'

BASE_VIDEO_INFO = 
    {'url' => 'H0MwvOJEBOM',
     'provider' => 'dummy',
     'title' => 'HOW 2 DRAW SANIC HEGEHOG',
     'duration' => 0,
     'playlist' => false,
     'position' => nil}

FAKE_SOCKETENV = {
  'REMOTE_ADDR' => '127.0.0.1'
}

def mock_user_id(opts={})
  opts[:user] ? "user_#{opts[:user].id}" : "anon_#{opts[:object_id]}"
end

def mock_user_name(opts={})
  opts[:user] ? Tripcode.encode(opts[:user].nick)[0] : opts[:name]
end

def mock_tripcode(name)
  Tripcode.encode(name)
end

def make_websocket
  socket = WebSocketApp.new
  socket.on_open
end

def mock_user_tripcode(opts={})
  opts[:user] ? Tripcode.encode(opts[:user].nick)[1] : opts[:tripcode]
end

def mock_user_data(opts={})
  {:id => mock_user_id(opts), :name => mock_user_name(opts), :tripcode => mock_user_tripcode(opts), :anon => opts[:user] ? false : true }
end

SUBSCRIPTIONS = SubscriberList.new
                            
describe WebSocketApp do
  before(:each) do
    Video.delete_all
    Channel.delete_all
    User.delete_all
    Ban.delete_all
    SUBSCRIPTIONS.reset
     
    @channel = Channel.create!(:name => 'v4c')
    @video = Video.create!(:title => BASE_VIDEO_INFO['title'],
                          :url => BASE_VIDEO_INFO['url'],
                          :duration => 60,
                          :provider => BASE_VIDEO_INFO['provider'])
    
    @video.update_attribute(:channel_id, @channel.id)
    @socket = WebSocketApp.new
  end
  
  describe "Authentication" do
    it "should accept an authentication token" do
      user = User.create!(:name => 'admin', :nick => 'admin', :password => 'password', :password_confirm => 'password')
      user.generate_auth_token!
      
      @socket.should_receive(:send_message).with({'t' => 'hello', 'user' => mock_user_data(:user => user, :object_id => @socket.object_id), 'api' => WebSocketApp::API_VERSION})
      @socket.process_message(FAKE_SOCKETENV, {'t' => 'auth', 'auth_token' => user.auth_token}.to_json)
    end
    
    it "should not accept invalid authentication tokens" do
      @socket.should_receive(:send_message).with({'t' => 'hello', 'user' => mock_user_data(:name => 'Anonymous', :object_id => @socket.object_id), 'api' => WebSocketApp::API_VERSION})
      @socket.process_message(FAKE_SOCKETENV, {'t' => 'auth', 'auth_token' => '123'}.to_json)
    end
    
    it "should not process commands until authenticated" do
      @socket.process_message(FAKE_SOCKETENV, {'t' => 'subscribe', 'channel_id' => @channel.id}.to_json)
      SUBSCRIPTIONS.user_id_in_channel_id?(@socket.user_id, @channel.id).should == false
      @socket.process_message(FAKE_SOCKETENV, {'t' => 'auth'}.to_json)
      @socket.process_message(FAKE_SOCKETENV, {'t' => 'subscribe', 'channel_id' => @channel.id}.to_json)
      SUBSCRIPTIONS.user_id_in_channel_id?(@socket.user_id, @channel.id).should == true
    end
    
    it "should process tripcodes" do
      uname, tripcode = mock_tripcode('frodo#123')
      @socket.should_receive(:send_message).with({'t' => 'hello', 'user' => mock_user_data(:name => uname, :tripcode => tripcode, :object_id => @socket.object_id), 'api' => WebSocketApp::API_VERSION})
      @socket.process_message(FAKE_SOCKETENV, {'t' => 'auth', 'name' => 'frodo#123', 'auth_token' => '123'}.to_json)
    end
    
    it "should process tripcodes for users too" do
      user = User.create!(:name => 'admin', :nick => 'admin#123', :password => 'password', :password_confirm => 'password')
      user.generate_auth_token!
      
      @socket.should_receive(:send_message).with({'t' => 'hello', 'user' => mock_user_data(:user => user, :object_id => @socket.object_id), 'api' => WebSocketApp::API_VERSION})
      @socket.process_message(FAKE_SOCKETENV, {'t' => 'auth', 'name' => 'ignore#123', 'auth_token' => user.auth_token}.to_json)
    end
    
    it "should reject banned ip addresses" do
      start = Time.now.utc
      Timecop.freeze(start) do
        Ban.create!(:ip => '127.0.0.1', :ended_at => start + 1.day, :comment => 'Closed')
        
        @socket.should_receive(:send_message).with({'t' => 'goaway', 'reason' => 'ban', 'comment' => 'Closed'})
        @socket.process_message(FAKE_SOCKETENV, {'t' => 'auth'}.to_json)
      end
    end
    
    it "should allow expired banned ip addresses" do
      start = Time.now.utc
      Timecop.freeze(start) do
        Ban.create!(:ip => '127.0.0.1', :ended_at => start + 1.day, :comment => 'Closed')
      end
      
      Timecop.freeze(start + 1.day + 1) do
        @socket.should_receive(:send_message).with({'t' => 'hello', 'user' => mock_user_data(:name => 'Anonymous', :object_id => @socket.object_id), 'api' => WebSocketApp::API_VERSION})
        @socket.process_message(FAKE_SOCKETENV, {'t' => 'auth'}.to_json)
      end
    end
    
    it "should not allow an anonymous connection to take the name of a user" do
      user = User.create!(:name => 'admin', :nick => 'admin#123', :password => 'password', :password_confirm => 'password')
      
      @socket.should_receive(:send_message).with({'t' => 'goaway', 'reason' => 'inuse'})
      @socket.process_message(FAKE_SOCKETENV, {'t' => 'auth', 'name' => 'admin#123'}.to_json)
    end
  end
  
  describe "Channel" do
    before do
      @socket.process_message(FAKE_SOCKETENV, {'t' => 'auth'}.to_json)
    end
    
    it "should subscribe the user to a valid channel" do
      #@socket.should_receive(:send_message).with({"t"=>"userjoined", "user"=>mock_user_data(:name => 'Anonymous', :object_id => @socket.object_id), "scope"=>""})
      @socket.process_message(FAKE_SOCKETENV, {'t' => 'subscribe', 'channel_id' => @channel.id}.to_json)
      SUBSCRIPTIONS.user_id_in_channel_id?(@socket.user_id, @channel.id).should == true
    end
    
    it "should not subscribe the user to an invalid channel" do
      @socket.should_receive(:send_message).with({"t"=>"goaway", "reason"=>"notfound"})
      @socket.process_message(FAKE_SOCKETENV, {'t' => 'subscribe', 'channel_id' => 0}.to_json)
      SUBSCRIPTIONS.user_id_in_channel_id?(@socket.user_id, @channel.id).should == false
    end
    
    it "should dispatch messages to subscribers" do
      @socket2 = WebSocketApp.new
      @socket2.process_message(FAKE_SOCKETENV, {'t' => 'auth'}.to_json)
    
      @socket.process_message(FAKE_SOCKETENV, {'t' => 'subscribe', 'channel_id' => @channel.id}.to_json)
      @socket2.process_message(FAKE_SOCKETENV, {'t' => 'subscribe', 'channel_id' => @channel.id}.to_json)
      
      #@socket.should_not_receive(:send_message)
      @socket.should_receive(:send_message).with({'t' => 'message', 'uid' => @socket.user_id, 'content' => 'HELLO'})
      @socket2.should_receive(:send_message).with({'t' => 'message', 'uid' => @socket.user_id, 'content' => 'HELLO'})
      @socket.process_message(FAKE_SOCKETENV, {'t' => 'message', 'content' => 'HELLO', 'channel_id' => @channel.id}.to_json)
    end
    
    it "should unsubscribe the user from a subscribed channel" do
      @socket.process_message(FAKE_SOCKETENV, {'t' => 'subscribe', 'channel_id' => @channel.id}.to_json)
      SUBSCRIPTIONS.should_receive(:unsubscribe).with(@socket, @channel)
      @socket.process_message(FAKE_SOCKETENV, {'t' => 'unsubscribe', 'channel_id' => @channel.id}.to_json)
    end
    
    # TODO: should we explicitly restrict 1 subscription to connection? sounds like an idea
    it "should only allow a connection do have 1 subscription" do
      @channel2 = Channel.create!(:name => 'chan2')
      
      @socket.process_message(FAKE_SOCKETENV, {'t' => 'subscribe', 'channel_id' => @channel.id}.to_json)
      SUBSCRIPTIONS.connection_in_channel_id?(@socket, @channel.id).should == true
      @socket.process_message(FAKE_SOCKETENV, {'t' => 'subscribe', 'channel_id' => @channel2.id}.to_json)
      SUBSCRIPTIONS.connection_in_channel_id?(@socket, @channel.id).should == false
      SUBSCRIPTIONS.connection_in_channel_id?(@socket, @channel2.id).should == true
    end
    
    it "usermod should allow anonymous change their name" do
      @socket.process_message(FAKE_SOCKETENV, {'t' => 'usermod', 'name' => 'frodo'}.to_json)
    end
    
    it "should list all videos in the channel" do
      @video2 = @channel.videos.create!(
        :title => BASE_VIDEO_INFO['title'],
        :url => BASE_VIDEO_INFO['url']+'2',
        :duration => 60,
        :provider => BASE_VIDEO_INFO['provider']
      )
      
      @socket.should_receive(:send_message).with({"t"=>"userjoined", "user"=>mock_user_data(:name => 'Anonymous', :object_id => @socket.object_id), "scope"=>""})
      @socket.should_receive(:send_message).with(@video.to_info.merge('t' => 'playlist_video'))
      @socket.should_receive(:send_message).with(@video2.to_info.merge('t' => 'playlist_video'))
      @socket.process_message(FAKE_SOCKETENV, {'t' => 'subscribe', 'channel_id' => @channel.id}.to_json)
    end
  end
  
  describe "Skip" do
    before do
      @video2 = @channel.videos.create!(
        :title => BASE_VIDEO_INFO['title'],
        :url => BASE_VIDEO_INFO['url']+'2',
        :duration => 60,
        :provider => BASE_VIDEO_INFO['provider']
      )
      @socket2 = WebSocketApp.new
      @socket.process_message(FAKE_SOCKETENV, {'t' => 'auth'}.to_json)
      @socket2.process_message(FAKE_SOCKETENV, {'t' => 'auth'}.to_json)
    
      @socket.process_message(FAKE_SOCKETENV, {'t' => 'subscribe', 'channel_id' => @channel.id}.to_json)
      @socket2.process_message(FAKE_SOCKETENV, {'t' => 'subscribe', 'channel_id' => @channel.id}.to_json)
      
      @channel.update_attribute(:skip_limit, 100)
    end
    
    it "should advance the skip count, skipping the video when the threshold has been reached" do
      now = Time.now.utc
      Timecop.freeze(now) do
        @channel.play_item(@video)
      
        @socket.should_receive(:send_message).with({"count" => 1, "t"=>"skip"})
        @socket2.should_receive(:send_message).with({"count" => 1, "t"=>"skip"})
        @socket.process_message(FAKE_SOCKETENV, {'t' => 'skip'}.to_json)
      
        @socket.should_receive(:send_message).with({"count" => 2, "t"=>"skip"})
        @socket2.should_receive(:send_message).with({"count" => 2, "t"=>"skip"})
        @socket.should_receive(:send_message).with(@video2.to_info.merge({'t' => 'video', 'time' => 0.0, 'force' => true}))
        @socket2.should_receive(:send_message).with(@video2.to_info.merge({'t' => 'video', 'time' => 0.0, 'force' => true}))
        @socket2.process_message(FAKE_SOCKETENV, {'t' => 'skip'}.to_json)
      end
    end
    
    it "should decrease the skip count with unskip" do
      @channel.play_item(@video)
    
      @socket.should_receive(:send_message).with({"count" => 1, "t"=>"skip"})
      @socket2.should_receive(:send_message).with({"count" => 1, "t"=>"skip"})
      @socket.process_message(FAKE_SOCKETENV, {'t' => 'skip'}.to_json)
    
      @socket.should_receive(:send_message).with({"count" => 0, "t"=>"skip"})
      @socket2.should_receive(:send_message).with({"count" => 0, "t"=>"skip"})
      @socket.process_message(FAKE_SOCKETENV, {'t' => 'unskip'}.to_json)
    
      @socket.should_receive(:send_message).with({"count" => 1, "t"=>"skip"})
      @socket2.should_receive(:send_message).with({"count" => 1, "t"=>"skip"})
      @socket2.process_message(FAKE_SOCKETENV, {'t' => 'skip'}.to_json)
    
      @socket.should_receive(:send_message).with({"count" => 0, "t"=>"skip"})
      @socket2.should_receive(:send_message).with({"count" => 0, "t"=>"skip"})
      @socket2.process_message(FAKE_SOCKETENV, {'t' => 'unskip'}.to_json)
    end
  end
  
  describe "Video" do
    before do
      @video2 = @channel.videos.create!(
        :title => BASE_VIDEO_INFO['title'],
        :url => BASE_VIDEO_INFO['url']+'2',
        :duration => 60,
        :provider => BASE_VIDEO_INFO['provider'],
        :playlist => true
      )
      
      @video.update_attribute(:playlist, true)
    end
    
    describe "For anonymous" do
      before do
        @socket.process_message(FAKE_SOCKETENV, {'t' => 'subscribe', 'channel_id' => @channel.id}.to_json)
      end
    
      it "should not accept any of these commands if the user is not a moderator or admin" do
        now = Time.now.utc
        Timecop.freeze(now) do
          @channel.play_item(@video)
          @channel.current_video.should == @video
          @channel.current_time.should == 0
          @socket.process_message(FAKE_SOCKETENV, {'t' => 'video', 'video_id' => @video2.id, 'channel_id' => @channel.id}.to_json)
          @channel.current_video.should == @video
          @socket.process_message(FAKE_SOCKETENV, {'t' => 'video', 'url' => 'http://www.youtube.com/watch?v=-a7AC9__lDo', 'channel_id' => @channel.id}.to_json)
          @channel.current_video.should == @video
          @channel.current_video.url.should == BASE_VIDEO_INFO['url']
          @socket.process_message(FAKE_SOCKETENV, {'t' => 'video_finished', 'channel_id' => @channel.id}.to_json)
          @channel.current_video.should == @video
          @socket.process_message(FAKE_SOCKETENV, {'t' => 'video_time', 'time' => 30, 'channel_id' => @channel.id}.to_json)
          @channel.current_time.should == 0
        end
      end
    end
    
    describe "For moderators" do
      before do
        @user = User.create!(:name => 'admin', :nick => 'admin', :password => 'password', :password_confirm => 'password')
        @user.generate_auth_token!
        Moderator.create!(:name => @user.nick, :channel_id => @channel.id)
        
        @socket.process_message(FAKE_SOCKETENV, {'t' => 'auth', 'auth_token' => @user.auth_token}.to_json)
        @socket.process_message(FAKE_SOCKETENV, {'t' => 'subscribe', 'channel_id' => @channel.id}.to_json)
      end
      
      it "video(video_id) should play an existing video from the playlist" do
        @channel.reload
        @socket.scope_for(@channel).should == 'mod'
        @video2.channel_id.should == @channel.id
        @socket.process_message(FAKE_SOCKETENV, {'t' => 'video', 'video_id' => @video2.id, 'channel_id' => @channel.id}.to_json)
        @channel.reload.current_video.should == @video2
      end
    
      it "video(url) should play a new video from the playlist" do
        @channel.reload
        @socket.scope_for(@channel).should == 'mod'
        @socket.process_message(FAKE_SOCKETENV, {'t' => 'video', 'url' => 'http://www.youtube.com/play?v=123456', 'channel_id' => @channel.id}.to_json)
        @channel.reload.current_video.url.should == '123456'
      end
    
      it "video_finished should advance to the next video" do
        @channel.play_item(@video)
        @channel.reload.current_video.should == @video
        @socket.scope_for(@channel).should == 'mod'
        @socket.process_message(FAKE_SOCKETENV, {'t' => 'video_finished', 'channel_id' => @channel.id}.to_json)
        @channel.reload.current_video.should == @video2
      end
    
      it "video_time should advance the video to the specified time" do
        now = Time.now.utc
        Timecop.freeze(now) do
          @channel.play_item(@video)
          @channel.reload.current_video.should == @video
          @socket.scope_for(@channel).should == 'mod'
          @socket.process_message(FAKE_SOCKETENV, {'t' => 'video_time', 'time' => 30, 'channel_id' => @channel.id}.to_json)
          @channel.reload.current_time.should == 30
        end
      end
    end
  end
end


