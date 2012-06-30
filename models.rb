%w{user channel video moderator ban}.each do |lib|
  require File.join(File.dirname(__FILE__), 'models', lib)
end
