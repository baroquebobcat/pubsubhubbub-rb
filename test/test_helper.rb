ENV['RACK_ENV'] = 'test'

require File.expand_path(File.join(File.dirname(__FILE__), "..", "init"))

require "rack/test"
require "contest"
require "override"
require "quietbacktrace"

class Test::Unit::TestCase
  include Rack::Test::Methods

  def setup
    # Uncomment if you want to reset the database
    # before each test.
    # Ohm.flush
  end

  def app
    Main.new
  end

  def assertEquals(a, b)
    assert_equal a, b
  end

  def assertTrue(value)
    assert value
  end

  def assertFalse(value)
    assert !value
  end

  def response_body()
    last_response.body
  end

  def response_code()
    last_response.status
  end

end

module Sinatra
  class Base
    def get_known_challenge
      'this_is_my_fake_challenge_string'
    end
    alias_method :get_random_challenge, :get_known_challenge
  end
end

