class ExtraChannelData < ActiveRecord::Migration
  def self.up
    add_column :channels, :permalink, :string
    add_index :channels, :permalink
  end

  def self.down
    remove_column :channels, :permalink
  end
end
