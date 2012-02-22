require 'spec_helper'

describe Ban do
  before(:each) do
    Ban.delete_all
  end
  
  it "should set/get a duration, -1 for unlimited" do
    now = Time.now.utc
    Timecop.freeze(now) do
      # +1000
      ban = Ban.create!(:ip => '127.0.0.1', :duration => 1000)
      ban.ended_at.to_i.should == (now+1000).to_i
      
      # -1 
      ban = Ban.create!(:ip => '127.0.0.1', :duration => -1)
      ban.ended_at.should == nil
    end
  end
  
  it "find_active_by_ip should find active bans" do
    now = Time.now.utc
    Timecop.freeze(now) do
      # +1000
      @ban1 = Ban.create!(:ip => '127.0.0.1', :duration => 1000)
      
      # -1 
      @ban2 = Ban.create!(:ip => '127.0.0.2', :duration => -1)
      
      Ban.find_active_by_ip('127.0.0.1').should == @ban1
      Ban.find_active_by_ip('127.0.0.2').should == @ban2
    end
    
    Timecop.freeze(now+1001) do
      Ban.find_active_by_ip('127.0.0.1').should == nil
      Ban.find_active_by_ip('127.0.0.2').should == @ban2
    end
  end
  
  it "should enumerate info" do
    now = Time.now.utc
    Timecop.freeze(now) do
      ban = Ban.create!(:ip => '127.0.0.1', :comment => 'Annoying', 'banned_by' => 'admin', 'banned_by_ip' => '127.0.0.1')
      ban.to_info.should == {
        'id' => ban.id,
        'ip' => '127.0.0.1',
        'created_at' => now.to_i,
        'ended_at' => 0,
        'comment' => 'Annoying'
      }
      
      ban.to_info(:admin => true).should == {
        'id' => ban.id,
        'ip' => '127.0.0.1',
        'created_at' => now.to_i,
        'ended_at' => 0,
        'comment' => 'Annoying',
        'banned_by' => 'admin',
        'banned_by_ip' => '127.0.0.1'
      }
    end
  end
end
