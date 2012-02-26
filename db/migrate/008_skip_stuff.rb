class SkipStuff < ActiveRecord::Migration
  def self.up
    add_column :channels, :skip_limit, :integer
    add_column :channels, :connection_limit, :integer
  end

  def self.down
    remove_column :channels, :skip_limit
    remove_column :channels, :connection_limit
  end
end
