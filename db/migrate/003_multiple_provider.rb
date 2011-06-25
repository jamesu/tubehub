class MultipleProvider < ActiveRecord::Migration
  def self.up
    add_column :videos, :provider, :string
  end

  def self.down
    remove_column :videos, :provider
  end
end
