require File.dirname(__FILE__) + '/../stories_helper'

class PublishHandlerTest < Test::Unit::TestCase

  def handle(method, options = {})
    if method.eql? 'get'
      get "/publish"
    else
      post "/publish", options
    end
  end

  setup do
    Ohm.flush

    @topic = 'http://example.com/first-url'
    @topic2 = 'http://example.com/second-url'
    @topic3 = 'http://example.com/third-url'
  end

  should "testDebugFormRenders" do
    handle('get')
    assertTrue(response_body().include? '<html>')
  end

  should "testBadMode" do
    handle('post',
           {'hub.mode'=> 'invalid',
            'hub.url'=> 'http://example.com'})
    assertEquals(400, response_code())
    assertTrue(response_body().include? 'hub.mode')
  end

  should "testNoUrls" do
    handle('post', 'hub.mode' => 'publish')
    assertEquals(400, response_code())
    assertTrue(response_body().include? 'hub.url')
  end

  should "testBadUrls" do
    handle('post',
           {'hub.mode'=> 'PuBLisH',
            'hub.url' => 'http://example.com/bad_url#fragment'})
    assertEquals(400, response_code())
    assertTrue(response_body().include? 'hub.url invalid')
  end

  should "testInsertion" do
    KnownFeed.create_from(@topic)
    KnownFeed.create_from(@topic2)
    KnownFeed.create_from(@topic3)
    handle('post',
           {'hub.mode' => 'PuBLisH',
            'hub.url' => [@topic,
                          @topic2,
                          @topic3]})
    assertEquals(204, response_code())
    expected_topics = [@topic, @topic2, @topic3].to_set.to_a
    inserted_topics = FeedToFetch.all.collect { |f| f.topic }
    assertEquals(expected_topics.sort, inserted_topics.sort)
  end

  should "testIgnoreUnknownFeed" do
    handle('post',
           {'hub.mode' => 'PuBLisH',
            'hub.url' => [@topic,
                          @topic2,
                          @topic3]})
    assertEquals(204, response_code())
    assertEquals([], FeedToFetch.all.to_a)
  end

  should "testDuplicateUrls" do
    KnownFeed.create_from(@topic)
    KnownFeed.create_from(@topic2)
    handle('post',
           {'hub.mode' => 'PuBLisH',
            'hub.url' => [@topic,
                          @topic,
                          @topic,
                          @topic,
                          @topic,
                          @topic,
                          @topic,
                          @topic2,
                          @topic2,
                          @topic2,
                          @topic2,
                          @topic2,
                          @topic2,
                          @topic2]})
    assertEquals(204, response_code())
    expected_topics = [@topic, @topic2].to_set.to_a
    inserted_topics = FeedToFetch.all.each.collect { |f| f.topic }
    assertEquals(expected_topics.sort, inserted_topics.sort)
  end

  # todo...

#  def testInsertFailure(self):
#    """Tests when a publish event fails insertion."""
#    old_insert = FeedToFetch.insert
#    try:
#      for exception in (db.Error(), apiproxy_errors.Error(),
#                        runtime.DeadlineExceededError()):
#        @classmethod
#        def new_insert(cls, *args):
#          raise exception
#        FeedToFetch.insert = new_insert
#        self.handle('post',
#                    ('hub.mode', 'PuBLisH'),
#                    ('hub.url', 'http://example.com/first-url'),
#                    ('hub.url', 'http://example.com/second-url'),
#                    ('hub.url', 'http://example.com/third-url'))
#        self.assertEquals(503, self.response_code())
#    finally:
#      FeedToFetch.insert = old_insert

  OTHER_STRING = '/~one:two/&='
  FUNNY = '/CaSeSeNsItIvE'

  should "testCaseSensitive" do
    """Tests that cases for topics URLs are preserved."""
    @topic += FUNNY
    @topic2 += FUNNY
    @topic3 += FUNNY
    KnownFeed.create_from(@topic)
    KnownFeed.create_from(@topic2)
    KnownFeed.create_from(@topic3)
    handle('post',
           {'hub.mode' => 'PuBLisH',
            'hub.url' => [@topic,
                          @topic2,
                          @topic3]})
    assertEquals(204, response_code())
    expected_topics = [@topic, @topic2, @topic3].to_set.to_a
    inserted_topics = FeedToFetch.all.collect { |f| f.topic }
    assertEquals(expected_topics.sort, inserted_topics.sort)
  end

  # todo...

#  def testNormalization(self):
#    """Tests that URLs are properly normalized."""
#    self.topic += OTHER_STRING
#    self.topic2 += OTHER_STRING
#    self.topic3 += OTHER_STRING
#    normalized = [
#        main.normalize_iri(t)
#        for t in [self.topic, self.topic2, self.topic3]]
#    db.put([KnownFeed.create(t) for t in normalized])
#    self.handle('post',
#                ('hub.mode', 'PuBLisH'),
#                ('hub.url', self.topic),
#                ('hub.url', self.topic2),
#                ('hub.url', self.topic3))
#    self.assertEquals(204, self.response_code())
#    inserted_topics = set(f.topic for f in FeedToFetch.all())
#    self.assertEquals(set(normalized), inserted_topics)
#
#  def testIri(self):
#    """Tests publishing with an IRI with international characters."""
#    topic = main.normalize_iri(self.topic + FUNNY_UNICODE)
#    topic2 = main.normalize_iri(self.topic2 + FUNNY_UNICODE)
#    topic3 = main.normalize_iri(self.topic3 + FUNNY_UNICODE)
#    normalized = [topic, topic2, topic3]
#    db.put([KnownFeed.create(t) for t in normalized])
#    self.handle('post',
#                ('hub.mode', 'PuBLisH'),
#                ('hub.url', self.topic + FUNNY_UTF8),
#                ('hub.url', self.topic2 + FUNNY_UTF8),
#                ('hub.url', self.topic3 + FUNNY_UTF8))
#    self.assertEquals(204, self.response_code())
#    inserted_topics = set(f.topic for f in FeedToFetch.all())
#    self.assertEquals(set(normalized), inserted_topics)
#
#  def testUnicode(self):
#    """Tests publishing with a URL that has unicode characters."""
#    topic = main.normalize_iri(self.topic + FUNNY_UNICODE)
#    topic2 = main.normalize_iri(self.topic2 + FUNNY_UNICODE)
#    topic3 = main.normalize_iri(self.topic3 + FUNNY_UNICODE)
#    normalized = [topic, topic2, topic3]
#    db.put([KnownFeed.create(t) for t in normalized])
#
#    payload = (
#        'hub.mode=publish'
#        '&hub.url=' + urllib.quote(self.topic) + FUNNY_UTF8 +
#        '&hub.url=' + urllib.quote(self.topic2) + FUNNY_UTF8 +
#        '&hub.url=' + urllib.quote(self.topic3) + FUNNY_UTF8)
#    self.handle_body('post', payload)
#    self.assertEquals(204, self.response_code())
#    inserted_topics = set(f.topic for f in FeedToFetch.all())
#    self.assertEquals(set(normalized), inserted_topics)
#
#  def testSources(self):
#    """Tests that derived sources are properly set on FeedToFetch instances."""
#    db.put([KnownFeed.create(self.topic),
#            KnownFeed.create(self.topic2),
#            KnownFeed.create(self.topic3)])
#    source_dict = {'one': 'two', 'three': 'four'}
#    topics = [self.topic, self.topic2, self.topic3]
#    def derive_sources(handler, urls):
#      self.assertEquals(set(topics), set(urls))
#      self.assertEquals('testvalue', handler.request.get('the-real-thing'))
#      return source_dict
#
#    main.hooks.override_for_test(main.derive_sources, derive_sources)
#    try:
#      self.handle('post',
#                  ('hub.mode', 'PuBLisH'),
#                  ('hub.url', self.topic),
#                  ('hub.url', self.topic2),
#                  ('hub.url', self.topic3),
#                  ('the-real-thing', 'testvalue'))
#      self.assertEquals(204, self.response_code())
#      for topic in topics:
#        feed_to_fetch = FeedToFetch.get_by_topic(topic)
#        found_source_dict = dict(zip(feed_to_fetch.source_keys,
#                                     feed_to_fetch.source_values))
#        self.assertEquals(source_dict, found_source_dict)
#    finally:
#      main.hooks.reset_for_test(main.derive_sources)
#

end
