require 'spec_helper'

describe User do
  before(:each) do
    User.delete_all
  end
  
  it "should only allow assignment of :name, :nick, :password, :password_confirm when user is a normal user" do
    user = User.create!(:name => 'user', :nick => 'user', :password => 'password', :password_confirm => 'password')
    user.admin.should == false
    admin = User.new(:name => 'admin', :nick => 'admin', :password => 'password', :password_confirm => 'password', :admin => true)
    admin.updated_by = user
    admin.name.should == 'admin'
    admin.nick.should == 'admin'
    admin.password.should == 'password'
    admin.password_confirm.should == 'password'
    admin.save
    admin.admin.should == false
    User.find_by_id(admin.id).admin.should == false
  end
  
  it "should allow assignment of :admin only when updated_by is an admin or nil" do
    # nil
    admin = User.create!(:name => 'admin', :nick => 'admin', :password => 'password', :password_confirm => 'password', :admin => true)
    admin.admin.should == true
    # == admin
    user = User.create!(:name => 'user', :nick => 'user', :password => 'password', :password_confirm => 'password')
    user.updated_by = admin
    user.admin = true
    user.save
    User.find_by_id(user.id).admin.should == true
  end
  
  it "should validate all fields on creation" do
    user = User.create()
    user.save.should == false
    
    user.should_not be_valid
    user.errors.get(:name).should == ["can't be blank"]
    user.errors.get(:nick).should == ["can't be blank"]
    user.errors.get(:password).should == ["can't be blank"]
  end
  
  it "should check the password is equal if set" do
    user = User.new(:name => 'admin', :nick => 'admin', :password => 'password', :password_confirm => 'password2')
    user.save.should == false
    user.errors.get(:password_confirm).should == ['Password needs to be confirmed']
  end
  
  it "should generate a valid salt and token when the password is set" do
    user = User.new(:name => 'admin', :nick => 'admin', :password => 'password', :password_confirm => 'password')
    user.save.should == true
    user.token.should_not == nil
    user.salt.should_not == nil
    
    old_token = user.token
    old_salt = user.salt
    
    user.update_attributes(:password => 'password2', :password_confirm => 'password2')
    user.save.should == true
    user.token.should_not == old_token
    user.salt.should_not == old_salt
  end
  
  it "should generate_auth_token" do
    user = User.new(:name => 'admin', :nick => 'admin', :password => 'password', :password_confirm => 'password')
    
    user.auth_token.should == nil
    user.generate_auth_token
    user.auth_token.should_not == nil
    
    # ! should save
    user.new_record?.should == true
    user.generate_auth_token!
    user.new_record?.should == false
  end
  
  it "should generate an eval_nick" do
    user = User.create!(:name => 'admin', :nick => 'admin', :password => 'password', :password_confirm => 'password', :nick => 'admin#123')
    user.eval_nick.should == Tripcode.encode('admin#123').join('')
  end
  
  it "should reveal admin to_info only when :admin=>true is passed" do
    user = User.create!(:name => 'admin', :nick => 'admin', :password => 'password', :password_confirm => 'password')
    user.to_info.should == {:id => user.id, :name => user.name, :nick => user.nick}
    user.to_info(:admin => true).should == {:id => user.id, :name => user.name, :nick => user.nick, :created_at => user.created_at.to_i, :updated_at => user.updated_at.to_i, :admin => user.admin}
  end
  
  it "should authenticate users" do
    user = User.create!(:name => 'admin', :nick => 'admin', :password => 'password', :password_confirm => 'password')
    
    User.authenticate('admin', 'password').should == user
    User.authenticate('user', 'password').should == nil
  end
end
