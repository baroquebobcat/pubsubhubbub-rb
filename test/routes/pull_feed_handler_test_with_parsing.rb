require File.dirname(__FILE__) + '/../stories_helper'

class PullFeedHandlerTestWithParsing < Test::Unit::TestCase
  include Mocha::API

  def handle(method, options = {})
    post "/work/pull_feeds", options
  end

  setup do
    Ohm.flush
  end

# handler_class = main.PullFeedHandler

#  def testPullBadContent(self):
#    """Tests when the content doesn't parse correctly."""
#    topic = 'http://example.com/my-topic'
#    callback = 'http://example.com/my-subscriber'
#    self.assertTrue(Subscription.insert(callback, topic, 'token', 'secret'))
#    FeedToFetch.insert([topic])
#    urlfetch_test_stub.instance.expect(
#        'get', topic, 200, 'this does not parse')
#    self.handle('post', ('topic', topic))
#    feed = FeedToFetch.get_by_key_name(get_hash_key_name(topic))
#    self.assertTrue(feed is None)
#
#  def testPullBadFeed(self):
#    """Tests when the content parses, but is not a good Atom document."""
#    data = ('<?xml version="1.0" encoding="utf-8"?>\n'
#            '<meep><entry>wooh</entry></meep>')
#    topic = 'http://example.com/my-topic'
#    callback = 'http://example.com/my-subscriber'
#    self.assertTrue(Subscription.insert(callback, topic, 'token', 'secret'))
#    FeedToFetch.insert([topic])
#    urlfetch_test_stub.instance.expect('get', topic, 200, data)
#    self.handle('post', ('topic', topic))
#    feed = FeedToFetch.get_by_key_name(get_hash_key_name(topic))
#    self.assertTrue(feed is None)
#
#  def testPullGoodAtom(self):
#    """Tests when the Atom XML can parse just fine."""
#    data = ('<?xml version="1.0" encoding="utf-8"?>\n<feed><my header="data"/>'
#            '<entry><id>1</id><updated>123</updated>wooh</entry></feed>')
#    topic = 'http://example.com/my-topic'
#    callback = 'http://example.com/my-subscriber'
#    self.assertTrue(Subscription.insert(callback, topic, 'token', 'secret'))
#    FeedToFetch.insert([topic])
#    urlfetch_test_stub.instance.expect('get', topic, 200, data)
#    self.handle('post', ('topic', topic))
#    feed = FeedToFetch.get_by_key_name(get_hash_key_name(topic))
#    self.assertTrue(feed is None)
#    event = EventToDeliver.all().get()
#    self.assertEquals(data.replace('\n', ''), event.payload.replace('\n', ''))
#
#  def testPullGoodRss(self):
#    """Tests when the RSS XML can parse just fine."""
#    data = ('<?xml version="1.0" encoding="utf-8"?>\n'
#            '<rss version="2.0"><channel><my header="data"/>'
#            '<item><guid>1</guid><updated>123</updated>wooh</item>'
#            '</channel></rss>')
#    topic = 'http://example.com/my-topic'
#    callback = 'http://example.com/my-subscriber'
#    self.assertTrue(Subscription.insert(callback, topic, 'token', 'secret'))
#    FeedToFetch.insert([topic])
#    urlfetch_test_stub.instance.expect('get', topic, 200, data)
#    self.handle('post', ('topic', topic))
#    feed = FeedToFetch.get_by_key_name(get_hash_key_name(topic))
#    self.assertTrue(feed is None)
#    event = EventToDeliver.all().get()
#    self.assertEquals(data.replace('\n', ''), event.payload.replace('\n', ''))
#
#  def testPullGoodRdf(self):
#    """Tests when the RDF (RSS 1.0) XML can parse just fine."""
#    data = ('<?xml version="1.0" encoding="utf-8"?>\n'
#            '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
#            '<channel><my header="data"/>'
#            '<item><guid>1</guid><updated>123</updated>wooh</item>'
#            '</channel></rdf:RDF>')
#    topic = 'http://example.com/my-topic'
#    callback = 'http://example.com/my-subscriber'
#    self.assertTrue(Subscription.insert(callback, topic, 'token', 'secret'))
#    FeedToFetch.insert([topic])
#    urlfetch_test_stub.instance.expect('get', topic, 200, data)
#    self.handle('post', ('topic', topic))
#    feed = FeedToFetch.get_by_key_name(get_hash_key_name(topic))
#    self.assertTrue(feed is None)
#    event = EventToDeliver.all().get()
#    self.assertEquals(data.replace('\n', ''), event.payload.replace('\n', ''))

end
