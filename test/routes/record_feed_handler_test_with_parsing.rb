require File.dirname(__FILE__) + '/../stories_helper'

class RecordFeedHandlerTest < Test::Unit::TestCase
  include Mocha::API

  def handle(method, options = {})
    post "/work/record_feeds", options
  end

  setup do
    Ohm.flush
  end

#  """Tests for the RecordFeedHandler that excercise parsing."""
#
#  handler_class = main.RecordFeedHandler
#
#  def testAtomParsing(self):
#    """Tests parsing an Atom feed."""
#    topic = 'http://example.com/atom'
#    feed_id = 'my-id'
#    data = ('<?xml version="1.0" encoding="utf-8"?>'
#            '<feed><id>my-id</id></feed>')
#    urlfetch_test_stub.instance.expect('GET', topic, 200, data)
#    self.handle('post', ('topic', topic))
#
#    known_id = KnownFeedIdentity.get(KnownFeedIdentity.create_key(feed_id))
#    feed = KnownFeed.get(KnownFeed.create_key(topic))
#    self.assertEquals([topic], known_id.topics)
#    self.assertEquals(feed.feed_id, feed_id)
#    self.assertEquals(feed.feed_id, known_id.feed_id)
#
#  def testRssParsing(self):
#    """Tests parsing an Atom feed."""
#    topic = 'http://example.com/rss'
#    feed_id = 'http://example.com/blah'
#    data = ('<?xml version="1.0" encoding="utf-8"?><rss><channel>'
#            '<link>http://example.com/blah</link></channel></rss>')
#    urlfetch_test_stub.instance.expect('GET', topic, 200, data)
#    self.handle('post', ('topic', topic))
#
#    known_id = KnownFeedIdentity.get(KnownFeedIdentity.create_key(feed_id))
#    feed = KnownFeed.get(KnownFeed.create_key(topic))
#    self.assertEquals([topic], known_id.topics)
#    self.assertEquals(feed.feed_id, feed_id)
#    self.assertEquals(feed.feed_id, known_id.feed_id)

end
