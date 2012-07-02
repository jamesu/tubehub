require './core'

# Single server mode

use Rack::Session::Cookie, :key => APP_CONFIG['cookie_name'],
                           :path => '/',
                           :expire_after => 14400, # In seconds
                           :secret => APP_CONFIG['cookie_key']

do_frontend = ENV['TUBEHUB_MODE'].nil? || ENV['TUBEHUB_MODE'] == 'frontend'
do_backend = ENV['TUBEHUB_MODE'].nil? || ENV['TUBEHUB_MODE'] == 'backend'

if do_backend
  map '/ws' do
    run WebSocketApp.new
  end
end

if do_frontend
  map '/' do
	  run App.new
  end
end