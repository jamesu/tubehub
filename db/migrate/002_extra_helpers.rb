class ExtraHelpers < ActiveRecord::Migration
  def self.up
    add_column :videos, :order, :integer
    add_column :videos, :url, :string
    add_column :channels, :start_time, :datetime
    add_column :channels, :current_video_id, :integer
    
    remove_column :videos, :video
    remove_column :videos, :offset
  end

  def self.down
    remove_column :videos, :order
    remove_column :videos, :url
    remove_column :channels, :start_time
    remove_column :channels, :current_video_id
    
    add_column :videos, :video, :string
    add_column :videos, :offset, :string
  end
end
