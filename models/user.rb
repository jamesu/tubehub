class User < ActiveRecord::Base
  before_validation :update_tokens
  attr_accessor :password, :password_confirm
  attr_accessor :last_set_time
  attr_accessor :updated_by
  
  has_and_belongs_to_many :admin_channels, :class_name => 'Channel', :join_table => 'channel_admins'
  
  attr_accessible :name, :nick, :password, :password_confirm, :admin
  
  validates_presence_of :name
  validates_presence_of :nick
  validates_uniqueness_of :name
  validates_uniqueness_of :nick
  validates_presence_of :password, :on => :create
  
  validate :check_password
  before_save :update_state
  
  def check_password
    if @password_confirm != @password
      errors.add(:password_confirm, 'Password needs to be confirmed')
    end
  end
  
  def update_tokens
    if @password && !@password.nil? && !@password.empty?
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
  
  def admin
    @new_admin || self[:admin]
  end
  
  def admin=(value)
    @new_admin = value
  end
  
  def update_state
    self[:eval_nick] = Tripcode.encode(nick).join('') if nick_changed? or new_record?
    self[:admin] = @new_admin if !@new_admin.nil? and (@updated_by.nil? or @updated_by.try(:admin) == true)
    @new_admin = nil
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
