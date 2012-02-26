require 'spec_helper'

describe App do
  before(:each) do
    User.destroy_all
    Channel.destroy_all
    Ban.destroy_all
    
    @channel = Channel.create!(:name => 'v4c', :banner => "Header here")
    
    @user = User.create(:name => 'user', :nick => 'user', :password => 'password', :password_confirm => 'password')
  end
  
  describe "/authentication" do
    it "should authenticate a user" do
      post '/auth', :name => 'user', :password => 'password'
      last_response.body.match(/Invalid login/).should == nil
    end
    
    it "should not authenticate a user with an invalid password" do
      post '/auth', :name => 'user', :password => 'password2'
      last_response.body.match(/Invalid login/).should_not == nil
    end
    
    it "should generate an auth token for users" do
      # Token for socket identification
      post '/auth/socket_token', {}, mock_login_session(@user)
      
      @user.reload.auth_token.should_not == nil
      JSON.parse(last_response.body).should == {'auth_token' => @user.auth_token}
    end
    
    it "should not generate an auth token for anonymous" do
      # Token for socket identification
      post '/auth/socket_token'
      last_response.status.should == 302
    end
  end
  
  describe "/users" do
    before do
      @user2 = User.create!({:name => 'sanic', :nick => 'sanic', :password => 'gottagofast', :password_confirm => 'gottagofast'})
    end
    
    it "should not allow non-admins to access this" do
      get '/users', {}, mock_login_session(@user)
      last_response.status.should == 401
      post '/users', {}, mock_login_session(@user)
      last_response.status.should == 401
      #put '/users/1', {}, mock_login_session(@user)
      #last_response.status.should == 401
      delete '/users/1', {}, mock_login_session(@user)
      last_response.status.should == 401
    end
    
    it "should return a list of users" do
      @user.update_attribute(:admin, true)
      get '/users', {}, mock_login_session(@user)
      
      data = JSON.parse(last_response.body)
      data.map{|u|u['name']}.sort.should == ['user', 'sanic'].sort
    end
    
    it "should return the current user but no other" do
      get "/users/#{@user.id}", {}, mock_login_session(@user)
      last_response.status.should == 200
      get "/users/#{@user2.id}", {}, mock_login_session(@user)
      last_response.status.should == 401
    end
    
    it "should return any user if they are an admin" do
      @user.update_attribute(:admin, true)
      get "/users/#{@user.id}", {}, mock_login_session(@user)
      last_response.status.should == 200
      get "/users/#{@user2.id}", {}, mock_login_session(@user)
      last_response.status.should == 200
    end
    
    it "should create a user" do
      @user.update_attribute(:admin, true)
      post '/users', {:name => 'tonic', :nick => 'tonic', :password => 'showeritup', :password_confirm => 'showeritup', :admin => true}.to_json, mock_login_session(@user)
      
      last_response.status.should == 201
      data = JSON.parse(last_response.body)
      User.find_by_id(data['id']).name.should == 'tonic'
      data['name'].should == 'tonic'
      data['admin'].should == true
    end
    
    it "should allow an admin to update another user" do
      @user.update_attribute(:admin, true)
      put "/users/#{@user2.id}", {'nick' => 'tonic', 'admin' => true}.to_json, mock_login_session(@user)
      last_response.status.should == 200
      
      data = JSON.parse(last_response.body)
      User.find_by_id(data['id']).should_not == nil
      @user2.reload.nick.should == 'tonic'
      @user2.admin.should == true
      data['nick'].should == 'tonic'
      data['admin'].should == true
    end
    
    it "should allow a user to update themselves" do
      put "/users/#{@user2.id}", {'nick' => 'tonic', 'admin' => true}.to_json, mock_login_session(@user2)
      last_response.status.should == 200
      
      data = JSON.parse(last_response.body)
      User.find_by_id(data['id']).should_not == nil
      @user2.reload.nick.should == 'tonic'
      @user2.admin.should == false
      data['nick'].should == 'tonic'
      data['admin'].should == false
    end
    
    it "should not allow a user to update anyone else" do
      put "/users/#{@user2.id}", {'nick' => 'tonic', 'admin' => true}.to_json, mock_login_session(@user)
      last_response.status.should == 401
      
      @user2.reload.nick.should_not == 'tonic'
    end
    
    it "should delete a user unless its the current user" do
      @user.update_attribute(:admin, true)
      delete "/users/#{@user.id}", {}, mock_login_session(@user)
      last_response.status.should == 406
      delete "/users/#{@user2.id}", {}, mock_login_session(@user)
      last_response.status.should == 200
      
      User.find_by_id(@user2.id).should == nil
    end
  end
  
  describe "/bans" do
    it "should not allow non-admins to access this" do
      get '/bans', {}, mock_login_session(@user)
      last_response.status.should == 401
      post '/bans', {}, mock_login_session(@user)
      last_response.status.should == 401
      put '/bans/1', {}, mock_login_session(@user)
      last_response.status.should == 401
      delete '/bans/1', {}, mock_login_session(@user)
      last_response.status.should == 401
    end
    
    it "should return a list of bans" do
      Ban.create!(:ip => '127.0.0.2')
      Ban.create!(:ip => '127.0.0.3')
      
      @user.update_attribute(:admin, true)
      get '/bans', {}, mock_login_session(@user)
      
      data = JSON.parse(last_response.body)
      data.map{|b|b['ip']}.sort.should == ['127.0.0.2', '127.0.0.3'].sort
    end
    
    it "should create a ban" do
      @user.update_attribute(:admin, true)
      now = Time.now.utc
      Timecop.freeze(now) do
        post '/bans', {:ip => '127.0.0.2', :comment => 'Ass', :duration => 1000}.to_json, mock_login_session(@user)
      end
      last_response.status.should == 201
      
      data = JSON.parse(last_response.body)
      Ban.find_by_id(data['id']).should_not == nil
      data['ip'].should == '127.0.0.2'
      data['comment'].should == 'Ass'
      data['created_at'].should == now.to_i
      data['ended_at'].should == (now+1000).to_i
    end
    
    it "should update a ban" do
      @user.update_attribute(:admin, true)
      now = Time.now.utc
      Timecop.freeze(now) do
        @ban = Ban.create!(:ip => '127.0.0.2')
        put "/bans/#{@ban.id}", {:duration => 1000}.to_json, mock_login_session(@user)
      end
      last_response.status.should == 200
      
      data = JSON.parse(last_response.body)
      Ban.find_by_id(data['id']).should_not == nil
      data['ended_at'].should == (now+1000).to_i
    end
    
    it "should delete a ban" do
      @user.update_attribute(:admin, true)
      now = Time.now.utc
      Timecop.freeze(now) do
        @ban = Ban.create!(:ip => '127.0.0.2')
        delete "/bans/#{@ban.id}", {}, mock_login_session(@user)
      end
      
      last_response.status.should == 200
      Ban.find_by_id(@ban.id).should == nil
    end
  end
  
  describe "/channels" do
    it "should not allow non-admins to access this" do
      get '/channels', {} # Apart from this
      last_response.status.should == 302
      post '/channels', {}, mock_login_session(@user)
      last_response.status.should == 401
      put '/channels/1', {}, mock_login_session(@user)
      last_response.status.should == 401
      delete '/channels/1', {}, mock_login_session(@user)
      last_response.status.should == 401
    end
    
    it "should return a list of channels" do
      @user.update_attribute(:admin, true)
      get '/channels', {}, mock_login_session(@user)
      
      data = JSON.parse(last_response.body)
      data[0]['name'].should == 'v4c'
      data[0]['banner'].should == 'Header here'
    end
    
    it "should get a channel" do
      @user.update_attribute(:admin, true)
      get "/channels/#{@channel.id}", {}, mock_login_session(@user)
      
      data = JSON.parse(last_response.body)
      data['name'].should == 'v4c'
      data['banner'].should == 'Header here'
    end
    
    it "should create a channel" do
      @user.update_attribute(:admin, true)
      post '/channels', {:name => 'b', :banner => 'Header here'}.to_json, mock_login_session(@user)
      
      last_response.status.should == 201
      data = JSON.parse(last_response.body)
      Channel.find_by_id(data['id']).should_not == nil
      data['name'].should == 'b'
      data['banner'].should == 'Header here'
    end
    
    it "should update a channel" do
      @user.update_attribute(:admin, true)
      put "/channels/#{@channel.id}", {:name => 'b2', :banner => 'Modified Header here'}.to_json, mock_login_session(@user)
      
      @channel.reload.name.should == 'b2'
      last_response.status.should == 200
      data = JSON.parse(last_response.body)
      data['id'].should == @channel.id
      data['name'].should == 'b2'
      data['banner'].should == 'Modified Header here'
    end
    
    it "should delete a channel" do
      @user.update_attribute(:admin, true)
      delete "/channels/#{@channel.id}", {}, mock_login_session(@user)
      
      last_response.status.should == 200
      Channel.find_by_id(@channel.id).should == nil
    end
  end
  
  describe "/stats" do
    it "should only be accessable by an admin" do
      get '/stats', {}, mock_login_session(@user)
      last_response.status.should == 401
      
      @user.update_attribute(:admin, true)
      get '/stats', {}, mock_login_session(@user)
      last_response.status.should == 200
    end
    
    it "should enumerate subscriptions and channels" do
      SUBSCRIPTIONS.should_receive(:stats_enumerate)
    
      @user.update_attribute(:admin, true)
      get '/stats', {}, mock_login_session(@user)
      
      data = JSON.parse(last_response.body)
      data['channels'].map{|c|c['id']}.should == [@channel.id]
    end
  end
  
  describe "/admin" do
    before do
      @user.update_attribute(:admin, true)
    end
    
    it "should only allow admins to /admin" do
      @user.update_attribute(:admin, false)
      get '/admin', {}, mock_login_session(@user)
      last_response.status.should == 401
      @user.update_attribute(:admin, true)
      get '/admin', {}, mock_login_session(@user)
      last_response.status.should == 200
    end
  end
end