class VideoMetadata < ActiveRecord::Migration
  def self.up
    add_column :videos, :title, :string
    add_column :videos, :duration, :float, :default => 0
    add_column :videos, :playlist, :boolean, :default => false
    remove_column :videos, :order
    add_column :videos, :position, :integer
  end

  def self.down
    remove_column :videos, :title
    remove_column :videos, :duration
    remove_column :videos, :playlist
    remove_column :videos, :position
    add_column :videos, :order, :float
  end
end
