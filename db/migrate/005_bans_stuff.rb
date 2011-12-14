class BansStuff < ActiveRecord::Migration
  def self.up
    create_table :bans do |t|
      t.string :ip
      t.datetime :created_at
      t.datetime :ended_at
      t.text :comment
    end
    
  end

  def self.down
    drop_table :bans
  end
end
