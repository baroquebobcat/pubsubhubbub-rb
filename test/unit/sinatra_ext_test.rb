require File.dirname(__FILE__) + '/../test_helper'

class MainTest < Test::Unit::TestCase

  # todo...
  should "have a valid url" do
    assert Sinatra::Base.new.is_valid_url("http://www.google.com")
  end

  # todo...
  should "support unicode/utf8" do
    assert_equal "http://www.google.com", Sinatra::Base.new.utf8encoded("http://www.google.com")
  end

  # todo...
  should "support iri" do
    assert_equal "http://www.google.com", Sinatra::Base.new.normalize_iri("http://www.google.com")  
  end

end
