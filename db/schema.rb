# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended to check this file into your version control system.

ActiveRecord::Schema.define(:version => 9) do

  create_table "bans", :force => true do |t|
    t.string   "ip"
    t.datetime "created_at"
    t.datetime "ended_at"
    t.text     "comment"
    t.string   "banned_by"
    t.string   "banned_by_ip"
  end

  create_table "channel_admins", :id => false, :force => true do |t|
    t.integer "channel_id"
    t.integer "user_id"
  end

  create_table "channels", :force => true do |t|
    t.integer  "user_id"
    t.string   "name"
    t.datetime "created_at",                          :null => false
    t.datetime "updated_at",                          :null => false
    t.datetime "start_time"
    t.integer  "current_video_id"
    t.string   "permalink"
    t.text     "banner"
    t.text     "footer"
    t.integer  "skip_limit"
    t.integer  "connection_limit"
    t.boolean  "locked",           :default => false
    t.integer  "video_limit"
    t.string   "backend_server"
  end

  add_index "channels", ["backend_server"], :name => "index_channels_on_backend_server"
  add_index "channels", ["permalink"], :name => "index_channels_on_permalink"
  add_index "channels", ["user_id"], :name => "index_channels_on_user_id"

  create_table "moderators", :force => true do |t|
    t.integer  "channel_id"
    t.string   "name"
    t.datetime "created_at", :null => false
    t.datetime "updated_at", :null => false
  end

  add_index "moderators", ["channel_id"], :name => "index_moderators_on_channel_id"

  create_table "users", :force => true do |t|
    t.string   "name"
    t.string   "salt"
    t.string   "token"
    t.string   "auth_token"
    t.datetime "created_at",                    :null => false
    t.datetime "updated_at",                    :null => false
    t.boolean  "admin",      :default => false
    t.string   "nick"
    t.string   "eval_nick"
  end

  add_index "users", ["name"], :name => "index_users_on_name"
  add_index "users", ["nick"], :name => "index_users_on_nick"

  create_table "videos", :force => true do |t|
    t.integer  "channel_id"
    t.integer  "user_id"
    t.datetime "created_at",                     :null => false
    t.datetime "updated_at",                     :null => false
    t.string   "url"
    t.string   "provider"
    t.string   "title"
    t.float    "duration",    :default => 0.0
    t.boolean  "playlist",    :default => false
    t.integer  "position"
    t.string   "added_by"
    t.string   "added_by_ip"
  end

  add_index "videos", ["channel_id"], :name => "index_videos_on_channel_id"

end
