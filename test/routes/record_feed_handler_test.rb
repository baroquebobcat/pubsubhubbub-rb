require File.dirname(__FILE__) + '/../stories_helper'

class RecordFeedHandlerTest < Test::Unit::TestCase
  include Mocha::API

  def handle(method, options = {})
    post "/work/record_feeds", options
  end

  setup do
    Ohm.flush

    @topic = 'http://www.example.com/meepa'
    @feed_id = 'my_feed_id'
    @content = 'my_atom_content'

  end

  def verify_update
    """Verifies the feed_id has been added for the topic."""
    feed_id = KnownFeedIdentity.get_by_key_name(KnownFeedIdentity.create_key(@feed_id))
    feed = KnownFeed.get_by_key_name(KnownFeed.create_key(@topic))

    assertEquals([@topic], feed_id.topics)
    assertEquals(feed.feed_id, @feed_id)
    assertEquals(feed.feed_id, feed_id.feed_id)
  end

  should "testNewFeed" do
    """Tests recording details for a known feed."""

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '200', :headers => {}, :body => @content)
    Net::HTTP.any_instance.expects(:request).once.returns(@http_mock)

    FeedIdentifier.any_instance.expects(:identify).with(@content, 'atom').once.returns(@feed_id)

    self.handle('post', {'topic' => @topic})
    self.verify_update
  end

  should "testNewFeedFetchFailure" do
    """Tests when fetching a feed to record returns a non-200 response."""

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '404', :headers => {}, :body => '')
    Net::HTTP.any_instance.expects(:request).once.returns(@http_mock)

    self.handle('post', {'topic' => @topic})
    feed = KnownFeed.get_by_key_name(KnownFeed.create_key(@topic))
    assertTrue(feed.feed_id.nil?)
  end

#  def testNewFeedFetchException(self):
#    """Tests when fetching a feed to record returns an exception."""
#    urlfetch_test_stub.instance.expect('GET', self.topic, 200, '',
#                                       urlfetch_error=True)
#    self.handle('post', ('topic', self.topic))
#    feed = KnownFeed.get(KnownFeed.create_key(self.topic))
#    assertTrue(feed.feed_id is None)

  should "testParseRetry" do
    """Tests when parsing as Atom fails, but RSS is successful."""

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '200', :headers => {}, :body => @content)
    Net::HTTP.any_instance.expects(:request).once.returns(@http_mock)

    FeedIdentifier.any_instance.expects(:identify).with(@content, 'atom').once.raises('Mock error')
    FeedIdentifier.any_instance.expects(:identify).with(@content, 'rss').once.returns(@feed_id)

    self.handle('post', {'topic' => @topic})
    self.verify_update
  end

  should "testParseFails" do
    """Tests when parsing completely fails."""

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '200', :headers => {}, :body => @content)
    Net::HTTP.any_instance.expects(:request).once.returns(@http_mock)

    FeedIdentifier.any_instance.expects(:identify).with(@content, 'atom').once.raises('Mock error')
    FeedIdentifier.any_instance.expects(:identify).with(@content, 'rss').once.raises('Mock error 2')

    self.handle('post', {'topic' => @topic})
    feed = KnownFeed.get_by_key_name(KnownFeed.create_key(@topic))
    assertTrue(feed.feed_id.nil?)
  end

  should "testParseFindsNoIds" do
    """Tests when no SAX exception is raised but no feed ID is found."""

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '200', :headers => {}, :body => @content)
    Net::HTTP.any_instance.expects(:request).once.returns(@http_mock)

    FeedIdentifier.any_instance.expects(:identify).with(@content, 'atom').once.returns(nil)
    FeedIdentifier.any_instance.expects(:identify).with(@content, 'rss').once.returns(nil)

    self.handle('post', {'topic'=> @topic})
    feed = KnownFeed.get_by_key_name(KnownFeed.create_key(@topic))
    assertTrue(feed.feed_id.nil?)
  end

  should "testExistingFeedNeedsRefresh" do
    """Tests recording details for an existing feed that needs a refresh."""
    KnownFeed.create(:topic => @topic)

    now = Time.now
    now += Main::FEED_IDENTITY_UPDATE_PERIOD + 1

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '200', :headers => {}, :body => @content)
    Net::HTTP.any_instance.expects(:request).once.returns(@http_mock)

    FeedIdentifier.any_instance.expects(:identify).with(@content, 'atom').once.returns(@feed_id)

    self.handle('post', {'topic' => @topic})
    self.verify_update
  end

  should "testExistingFeedNoRefresh" do
    """Tests recording details when the feed does not need a refresh."""
    feed = KnownFeed.create(:topic => @topic)
    feed.feed_id = 'meep'
    feed.save
    self.handle('post', {'topic' => @topic})
    # Confirmed by no calls to urlfetch or feed_identifier.
  end

  should "testExistingFeedNoIdRefresh" do
    """Tests that a KnownFeed with no ID will be refreshed."""
    feed = KnownFeed.create(:topic=>@topic)

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '200', :headers => {}, :body => @content)
    Net::HTTP.any_instance.expects(:request).once.returns(@http_mock)

    FeedIdentifier.any_instance.expects(:identify).with(@content, 'atom').once.returns(@feed_id)

    self.handle('post', {'topic' => @topic})
    self.verify_update
  end

  should "testNewFeedRelation" do
    """Tests when the feed ID relation changes for a topic."""
    KnownFeedIdentity.update(@feed_id, @topic)
    feed = KnownFeed.create(:topic=>@topic)
    feed.feed_id = @feed_id
    feed.save

    now = Time.now
    now += Main::FEED_IDENTITY_UPDATE_PERIOD + 1
    Time.stubs(:now).at_least_once.returns(now)

    new_feed_id = 'other_feed_id'

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '200', :headers => {}, :body => @content)
    Net::HTTP.any_instance.expects(:request).once.returns(@http_mock)

    FeedIdentifier.any_instance.expects(:identify).with(@content, 'atom').once.returns(new_feed_id)

    self.handle('post', {'topic' => @topic})

    feed_id = KnownFeedIdentity.get_by_key_name(KnownFeedIdentity.create_key(new_feed_id))
    feed = KnownFeed.get_by_key_name(feed.key_name)

    assertEquals([@topic], feed_id.topics)
    assertEquals(feed.feed_id, new_feed_id)
    assertEquals(feed.feed_id, feed_id.feed_id)

    # Old KnownFeedIdentity should have been deleted.
    assertTrue(KnownFeedIdentity.get_by_key_name(
            KnownFeedIdentity.create_key(@feed_id)).nil?)

  end

end
