ENV['RACK_ENV'] = 'test'

require "#{File.dirname(__FILE__)}/../core"
require 'rspec'
require 'rack/test'

# Use the following mixin to wire up rack/test and sinatra
module RSpecMixin
  include Rack::Test::Methods
  def app() App.new end
end

RSpec.configure do |c| 
  c.include RSpecMixin
end