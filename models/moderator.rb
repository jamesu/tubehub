class Moderator < ActiveRecord::Base
  belongs_to :channel
  
  def to_info(options={})
    {:name => name}
  end
end
