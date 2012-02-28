require 'spec_helper'

describe SubscriberList do
  before(:each) do
    User.destroy_all
    Channel.destroy_all
    Moderator.destroy_all
    
    @list = SUBSCRIPTIONS
    SUBSCRIPTIONS.reset
    
    @channel = Channel.create!(:name => 'v4c')
    @channel2 = Channel.create!(:name => 'vop')
    
    @admin = User.create(:name => 'admin', :nick => 'admin', :password => 'password', :password_confirm => 'password')
    @admin.update_attribute(:admin, true)
    
    @chan_admin = User.create!(:name => 'mod', :nick => 'mod', :password => 'password', :password_confirm => 'password')
    @channel.admin_channels << @chan_admin
    @mod_name, @mod_tripcode = ['frodo', '!123456']
    Moderator.create!(:channel_id => @channel.id, :name => 'frodo!123456')
  end
  
  it "subscribed users should have the appropriate name and scope" do
    @observer = FakeConnection.new
    @con = FakeConnection.new(@admin)
    @con2 = FakeConnection.new(@chan_admin)
    @con3 = FakeConnection.new(nil, @mod_name, @mod_tripcode)
    @con4 = FakeConnection.new()
    
    @list.subscribe(@observer, @channel)
    @list.subscribe(@con, @channel)
    @list.subscribe(@con2, @channel)
    @list.subscribe(@con3, @channel)
    @list.subscribe(@con4, @channel)
    
    @observer.messages[1]['scope'].should == 'sumin'
    @observer.messages[2]['scope'].should == 'admin'
    @observer.messages[3]['scope'].should == 'mod'
    @observer.messages[4]['scope'].should == ''
  end
  
  it "users should get notifications about connections and disconnections" do
    @con1 = FakeConnection.new
    @con2 = FakeConnection.new
    
    @list.subscribe(@con1, @channel)
    @list.subscribe(@con2, @channel)
    
    @con1.messages[1]['t'].should == 'userjoined'
    @con1.messages[1]['user'][:id].should == @con2.user_id
    
    # Global unsubscribe
    @list.unsubscribe(@con2)
    @con1.messages[2]['t'].should == 'userleft'
    @con1.messages[2]['user'][:id].should == @con2.user_id
    
    # Channel unsubscribe
    @list.subscribe(@con2, @channel)
    @list.unsubscribe(@con2, @channel)
    @con1.messages[3]['t'].should == 'userjoined'
    @con1.messages[3]['user'][:id].should == @con2.user_id
    @con1.messages[4]['t'].should == 'userleft'
    @con1.messages[4]['user'][:id].should == @con2.user_id
  end
  
  it "has_channel_id? should return true when we have subscribers in a channel" do
    @con1 = FakeConnection.new
    
    @list.subscribe(@con1, @channel)
    
    @list.has_channel_id?(@channel.id).should == true
    @list.has_channel_id?(@channel2.id).should == false
  end
  
  it "connection_in_channel_id? should return if a socket is connected to a channel" do
    @con1 = FakeConnection.new
    @con2 = FakeConnection.new
    
    @list.subscribe(@con1, @channel)
    @list.subscribe(@con2, @channel2)
    
    @list.connection_in_channel_id?(@con1, @channel.id).should == true
    @list.connection_in_channel_id?(@con2, @channel.id).should == false
    @list.connection_in_channel_id?(@con2, @channel2.id).should == true
    @list.connection_in_channel_id?(@con1, @channel2.id).should == false
  end
  
  it "user_in_channel_id? should return if a user is connected to a channel" do
    @con1 = FakeConnection.new(@admin)
    @con2 = FakeConnection.new(@chan_admin)
    
    @list.subscribe(@con1, @channel)
    @list.subscribe(@con2, @channel2)
    
    @list.user_in_channel_id?(@admin, @channel.id).should == true
    @list.user_in_channel_id?(@chan_admin, @channel.id).should == false
    @list.user_in_channel_id?(@chan_admin, @channel2.id).should == true
    @list.user_in_channel_id?(@admin, @channel2.id).should == false
  end
  
  it "user_id_in_channel_id? should return if a user id is connected to a channel" do
    @con1 = FakeConnection.new()
    @con2 = FakeConnection.new()
    
    @list.subscribe(@con1, @channel)
    @list.subscribe(@con2, @channel2)
    
    @list.user_id_in_channel_id?(@con1.user_id, @channel.id).should == true
    @list.user_id_in_channel_id?(@con2.user_id, @channel.id).should == false
    @list.user_id_in_channel_id?(@con2.user_id, @channel2.id).should == true
    @list.user_id_in_channel_id?(@con1.user_id, @channel2.id).should == false
  end 
  
  it "send_message should send a message to 1 or more channels" do
    @con1 = FakeConnection.new()
    @con2 = FakeConnection.new()
    
    @list.subscribe(@con1, @channel)
    @list.subscribe(@con2, @channel2)
    
    @list.send_message([@channel, @channel2], '123', {'test' => 1})
    
    @con1.messages.last['t'].should == '123'
    @con2.messages.last['t'].should == '123'
  end
  
  it "send_message should broadcast a message to a channel" do
    @con1 = FakeConnection.new()
    @con2 = FakeConnection.new()
    
    @list.subscribe(@con1, @channel)
    @list.subscribe(@con2, @channel2)
    
    @list.send_message(@channel, '123', {'test' => 1})
    
    @con1.messages.last['t'].should == '123'
    @con2.messages.last['t'].should_not == '123'
  end
  
  it "kick should kick users except admins" do
    @con1 = FakeConnection.new(@admin)
    @con2 = FakeConnection.new()
    
    @list.register_connection(@con1)
    @list.register_connection(@con2)
    
    @list.subscribe(@con1, @channel)
    @list.subscribe(@con2, @channel2)
    
    @con1.should_not_receive(:close)
    @con2.should_receive(:close)
    
    @list.kick(@con1.user_id)
    @list.kick(@con2.user_id)
  end
  
  describe "timer" do
    before do
      @observer = FakeConnection.new
      @observer2 = FakeConnection.new

      @list.subscribe(@observer, @channel)
      @list.subscribe(@observer2, @channel2)
      
      @now = Time.now.utc
      
      Timecop.freeze(@now) do
        @video = Video.new(:channel_id => @channel.id,
                              :title => BASE_VIDEO_INFO['title'],
                              :url => BASE_VIDEO_INFO['url'],
                              :duration => 60.0,
                              :provider => BASE_VIDEO_INFO['provider'],
                              :added_by => BASE_VIDEO_INFO['added_by'],
                              :playlist => true)
        @video.save
      end
    end
    
    it "should advance videos in all channels" do
      @channel.should_receive(:next_video!)
      @channel2.should_receive(:next_video!)
      @list.do_timer
    end
    
    it "should not advance videos for channels with leaders" do
      @observer.leader = true
      @channel.should_not_receive(:next_video!)
      @channel2.should_receive(:next_video!)
      @list.do_timer
    end
    
    it "should leave a 2 second gap between videos" do
      #nope
      Timecop.freeze(@now) do
        @channel.play_item(@video)
        @list.do_timer
      end
      
      #nope
      Timecop.freeze(@now + 60.seconds) do
        @list.do_timer
        @channel.current_time.should == 60
      end
      
      #yes
      Timecop.freeze(@now + 62.seconds) do
        @list.do_timer
        @channel.current_time.should == 0
      end
    end
  end
end

