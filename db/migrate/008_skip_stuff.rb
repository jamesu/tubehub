class SkipStuff < ActiveRecord::Migration
  def self.up
    add_column :channels, :skip_limit, :integer
    add_column :channels, :connection_limit, :integer
    
    add_column :channels, :locked, :boolean, :default => false
    add_column :channels, :video_limit, :integer
  end

  def self.down
    remove_column :channels, :skip_limit
    remove_column :channels, :connection_limit
    remove_column :channels, :locked
    remove_column :channels, :video_limit
  end
end
