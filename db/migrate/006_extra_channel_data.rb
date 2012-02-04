class ExtraChannelData < ActiveRecord::Migration
  def self.up
    add_column :channels, :permalink, :string
    add_index :channels, :permalink
    
    add_column :videos, :added_by, :string
    add_column :videos, :added_by_ip, :string
    
    add_column :users, :admin, :boolean, :default => false
  end

  def self.down
    remove_column :channels, :permalink
    remove_column :videos, :added_by
    remove_column :videos, :added_by_ip
    
    remove_column :users, :admin
  end
end
