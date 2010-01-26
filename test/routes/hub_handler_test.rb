require "stories_helper"

class HubHandlerTest < Test::Unit::TestCase

  should "show the hub page" do
    get "/"

    assert_equal "text/html", last_response.content_type
    assert last_response.body.include? 'Welcome to the demo PubSubHubbub reference Hub server!'
  end

  should "not publish, missing hub.mode" do
    post "/"

    assert "400", last_response.status
    assert_equal "text/html", last_response.content_type
    assert_equal 'hub.mode is invalid', last_response.body
  end

  should "not publish, missing hub.url" do
    post "/", "hub.mode" => "publish"

    assert "400", last_response.status
    assert_equal "text/plain", last_response.content_type
    assert_equal "MUST supply at least one hub.url parameter", last_response.body
  end

  should "publish" do
    post "/", { "hub.mode" => "publish", "hub.url" => ["http://www.google.com"] }

    assert "204", last_response.status
    assert_equal "", last_response.body
  end

  should "subscribe" do
    post "/", {}

  end

  should "unsubscribe" do
    post "/"
  end
end
