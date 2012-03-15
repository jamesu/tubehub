require './core'

use Rack::Session::Cookie, :key => '__tubehub',
                         :path => '/',
                         :expire_after => 14400, # In seconds
                         :secret => '1209iFNSJDNF*8&Y&YHH__'

map '/ws' do
  run WebSocketApp.new
end

map '/' do
  run App.new
end