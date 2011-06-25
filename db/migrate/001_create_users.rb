class CreateUsers < ActiveRecord::Migration
  def self.up
    create_table :users do |t|
      t.string  :name
      t.string  :salt
      t.string  :token
      t.string  :auth_token
      t.timestamps
    end
    
    create_table :channels do |t|
      t.integer :user_id
      t.string  :name
      t.timestamps
    end
    
    create_table :videos do |t|
      t.integer :channel_id
      t.integer :user_id
      t.string  :video
      t.string  :offset
      t.timestamps
    end
    
    add_index :users, :name
    add_index :channels, :user_id
    add_index :videos, :channel_id
  end

  def self.down
    drop_table :users
    drop_table :channels
    drop_table :videos
  end
end
