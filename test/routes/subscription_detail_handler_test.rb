require "stories_helper"

class SubscriptionDetailsHandlerTest < Test::Unit::TestCase

  should "show subsciptions" do
    get "/subscription-details", 'hub.url' => "http://top.ic", 'hub.callback' => 'foo', 'hub.secret' => 'asercet'
    
    assert_equal "text/html", last_response.content_type

#    assert last_response.body.include? 'http://top.ic'
#    assert last_response.body.include? 'Could not find any record for topic URL: http://top.ic'
  end

end
