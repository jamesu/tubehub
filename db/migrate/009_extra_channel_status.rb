class ExtraChannelStatus < ActiveRecord::Migration
  def self.up
    add_column :channels, :backend_server, :string, :default => nil
    add_index :channels, :backend_server
  end

  def self.down
    remove_column :channels, :backend_server
  end
end
