require "stories_helper"

class TopicDetailsHandlerTest < Test::Unit::TestCase

  should "show details" do
    get "/topic-details", 'hub.url' => "http://top.ic"

    assert_equal "text/html", last_response.content_type
    assert last_response.body.include? 'http://top.ic'
    assert last_response.body.include? 'Could not find any record for topic URL: http://top.ic'
  end

end
