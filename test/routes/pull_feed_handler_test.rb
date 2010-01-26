require File.dirname(__FILE__) + '/../stories_helper'

class PullFeedHandlerTest < Test::Unit::TestCase

  include Mocha::API

  def handle(method, options = {})
    post "/work/pull_feeds", options
  end

  setup do
    Ohm.flush

    @topic = 'http://example.com/my-topic-here'
    @header_footer = '<feed>this is my test header footer</feed>'
    @all_ids = ['1', '2', '3']
    @entry_payloads =
            @all_ids.each.collect do |entry_id|
              "content#{entry_id}"
            end
    @entry_list =
            @all_ids.each.collect do |entry_id|
              FeedEntryRecord.create_entry_for_topic(
                      @topic, entry_id, "content#{entry_id}")
            end
    @expected_response = 'the expected response data'
    @etag = 'something unique'
    @last_modified = 'some time'
    @headers = {
            'ETag'=> @etag,
            'Last-Modified'=> @last_modified,
            'Content-Type'=> 'application/atom+xml',
            }
    @expected_exceptions = []

    @callback = 'http://example.com/my-subscriber'
    assertTrue(Subscription.insert(
            @callback, @topic, 'token', 'secret'))

    FindFeedUpdates.any_instance.expects(
            :find_feed_updates).at_least_once.returns([@header_footer, @entry_list, @entry_payloads])

  end

  should "testNoWork" do
    self.handle('post', {'topic' => @topic})
  end

  should "testNewEntries_Atom" do
    """Tests when new entries are found."""
    FindFeedUpdates.any_instance.expects(
            :find_feed_updates).with('http://example.com/my-topic-here', 'atom', 'the expected response data').at_least_once.returns([@header_footer, @entry_list, @entry_payloads])

    FeedToFetch.insert([@topic])

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '200', :headers => @headers, :body => @expected_response)
    Net::HTTP.any_instance.expects(:request).at_least_once.returns(@http_mock)

    self.handle('post', {'topic', @topic})

    # Verify that all feed entry records have been written along with the
    # EventToDeliver and FeedRecord.

    feed_entries = FeedEntryRecord.get_entries_for_topic(
            @topic, @all_ids)

    assertEquals(@all_ids.sort, feed_entries.each.collect {|e| e.entry_id }.sort)

    work = EventToDeliver.all.first
    event_key = work.key_name
    assertEquals(@topic, work.topic)
    assertTrue(work.payload.include? 'content1\ncontent2\ncontent3')
    work.delete()

    record = FeedRecord.get_or_create(@topic)

    assertEquals(@header_footer, record.header_footer)
    assertEquals(@etag, record.etag)
    assertEquals(@last_modified, record.last_modified)
    assertEquals('application/atom+xml', record.content_type)

    tasks = TaskQueue.all(EventToDeliver::EVENT_QUEUE)
    assert_equal 1, tasks.size
    task = tasks[0]
    assertEquals(event_key, task.params['event_key'])

    tasks = TaskQueue.all(FeedToFetch::FEED_QUEUE)
    assert_equal 1, tasks.size
    task = tasks[0]
    assertEquals(@topic, task.params['topic'])

  end


  should "testRssFailBack" do
    """Tests when parsing as Atom fails and it uses RSS instead."""
    FindFeedUpdates.any_instance.expects(
            :find_feed_updates).once.raises('whoops')
    @header_footer = '<rss><channel>this is my test</channel></rss>'
    @headers['Content-Type'] = 'application/xml'

    FeedToFetch.insert([@topic])

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '200', :headers => @headers, :body => @expected_response)
    Net::HTTP.any_instance.expects(:request).at_least_once.returns(@http_mock)

    self.handle('post', {'topic' => @topic})

    feed_entries = FeedEntryRecord.get_entries_for_topic(
            @topic, @all_ids)
    assertEquals(@all_ids.sort, feed_entries.each.collect {|e| e.entry_id }.sort)

    work = EventToDeliver.all.first
    event_key = work.key_name
    assertEquals(@topic, work.topic)
    assertTrue(work.payload.include? 'content1\ncontent2\ncontent3')
    work.delete()

    record = FeedRecord.get_or_create(@topic)
    assertEquals('application/xml', record.content_type)

    tasks = TaskQueue.all(EventToDeliver::EVENT_QUEUE)
    assert_equal 1, tasks.size
    task = tasks[0]
    assertEquals(event_key, task.params['event_key'])

    tasks = TaskQueue.all(FeedToFetch::FEED_QUEUE)
    assert_equal 1, tasks.size
    task = tasks[0]
    assertEquals(@topic, task.params['topic'])

  end

  should "testAtomFailBack" do
    """Tests when parsing as RSS fails and it uses Atom instead."""
    FindFeedUpdates.any_instance.expects(
            :find_feed_updates).once.raises('whoops')
    @headers.clear
    @headers['Content-Type'] = 'application/rss+xml'
    info = FeedRecord.get_or_create(@topic)
    info.update(@headers)
    info.save

    FeedToFetch.insert([@topic])

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '200', :headers => @headers, :body => @expected_response)
    Net::HTTP.any_instance.expects(:request).at_least_once.returns(@http_mock)

    self.handle('post', {'topic' => @topic})

    feed_entries = FeedEntryRecord.get_entries_for_topic(
            @topic, @all_ids)
    assertEquals(@all_ids.sort, feed_entries.each.collect {|e| e.entry_id }.sort)

    work = EventToDeliver.all.first
    event_key = work.key_name
    assertEquals(@topic, work.topic)
    assertTrue(work.payload.include? 'content1\ncontent2\ncontent3')
    work.delete()

    record = FeedRecord.get_or_create(@topic)
    assertEquals('application/rss+xml', record.content_type)

    tasks = TaskQueue.all(EventToDeliver::EVENT_QUEUE)
    assert_equal 1, tasks.size
    task = tasks[0]
    assertEquals(event_key, task.params['event_key'])

    tasks = TaskQueue.all(FeedToFetch::FEED_QUEUE)
    assert_equal 1, tasks.size
    task = tasks[0]
    assertEquals(@topic, task.params['topic'])

  end

  should "testParseFailure" do
    """Tests when the feed cannot be parsed as Atom or RSS."""
    FindFeedUpdates.any_instance.expects(
            :find_feed_updates).at_least_once.raises('whoops')
    FeedToFetch.insert([@topic])

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '200', :headers => @headers, :body => @expected_response)
    Net::HTTP.any_instance.expects(:request).at_least_once.returns(@http_mock)

    self.handle('post', {'topic' => @topic})

    feed = FeedToFetch.get_by_key_name(FeedToFetch.get_hash_key_name(@topic))
    assertTrue(feed.nil?)

    tasks = TaskQueue.all(EventToDeliver::EVENT_QUEUE)
    assert_equal 0, tasks.size

    tasks = TaskQueue.all(FeedToFetch::FEED_QUEUE)
    assert_equal 1, tasks.size
    tasks.each do |t|
      assertEquals([@topic], t.params['topic'].to_a)
    end

  end

  should "testCacheHit" do
    """Tests when the fetched feed matches the last cached version of it."""
    info = FeedRecord.get_or_create(@topic)
    info.update(@headers)
    info.save

    @request_headers = {
            'If-None-Match' => @etag,
            'If-Modified-Since' => @last_modified,
            }

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '304', :headers => @headers, :body => @expected_response)
    Net::HTTP.any_instance.expects(:request).at_least_once.returns(@http_mock)

    self.handle('post', {'topic' => @topic})

    assertTrue(EventToDeliver.all().size == 0)

    tasks = TaskQueue.all(EventToDeliver::EVENT_QUEUE)
    assert_equal 0, tasks.size
  end

  should "testNoNewEntries" do
    """Tests when there are no new entries."""
    FeedToFetch.insert([@topic])
    @entry_list = []


    FindFeedUpdates.any_instance.expects(
            :find_feed_updates).with('http://example.com/my-topic-here', 'atom', 'the expected response data').at_least_once.returns([@header_footer, @entry_list, @entry_payloads])

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '200', :headers => @headers, :body => @expected_response)
    Net::HTTP.any_instance.expects(:request).at_least_once.returns(@http_mock)

    self.handle('post', {'topic' => @topic})

    assertTrue(EventToDeliver.all().size == 0)
    tasks = TaskQueue.all(EventToDeliver::EVENT_QUEUE)
    assert_equal 0, tasks.size

    record = FeedRecord.get_or_create(@topic)

    assertEquals(@header_footer, record.header_footer)
    assertEquals(@etag, record.etag)
    assertEquals(@last_modified, record.last_modified)
    assertEquals('application/atom+xml', record.content_type)
  end


# def testPullError(self):
#   """Tests when URLFetch raises an exception."""
#   FeedToFetch.insert([self.topic])
#   urlfetch_test_stub.instance.expect(
#       'get', self.topic, 200, self.expected_response, urlfetch_error=True)
#   self.handle('post', ('topic', self.topic))
#   feed = FeedToFetch.get_by_key_name(get_hash_key_name(self.topic))
#   self.assertEquals(1, feed.fetching_failures)
#   testutil.get_tasks(main.EVENT_QUEUE, expected_count=0)
#   tasks = testutil.get_tasks(main.FEED_QUEUE, expected_count=1)
#   tasks.extend(testutil.get_tasks(main.FEED_RETRIES_QUEUE, expected_count=1))
#   self.assertEquals([self.topic] * 2, [t['params']['topic'] for t in tasks])
#

  should "testPullBadStatusCode" do
    """Tests when the response status is bad."""
    FeedToFetch.insert([@topic])

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '500', :headers => @headers, :body => @expected_response)
    Net::HTTP.any_instance.expects(:request).at_least_once.returns(@http_mock)

    self.handle('post', {'topic' => @topic})

    feed = FeedToFetch.get_by_key_name(FeedToFetch.get_hash_key_name(@topic))
    assertEquals(1, feed.fetching_failures.to_i)

    tasks = TaskQueue.all(EventToDeliver::EVENT_QUEUE)
    assert_equal 0, tasks.size

    tasks = TaskQueue.all(FeedToFetch::FEED_RETRIES_QUEUE)
    assert_equal 1, tasks.size

    tasks.each do |t|
      assertEquals([@topic], t.params['topic'].to_a)
    end

  end

# def testApiProxyError(self):
#   """Tests when the APIProxy raises an error."""
#   FeedToFetch.insert([self.topic])
#   urlfetch_test_stub.instance.expect(
#       'get', self.topic, 200, self.expected_response, apiproxy_error=True)
#   self.handle('post', ('topic', self.topic))
#   feed = FeedToFetch.get_by_key_name(get_hash_key_name(self.topic))
#   self.assertEquals(1, feed.fetching_failures)
#   testutil.get_tasks(main.EVENT_QUEUE, expected_count=0)
#   tasks = testutil.get_tasks(main.FEED_QUEUE, expected_count=1)
#   tasks.extend(testutil.get_tasks(main.FEED_RETRIES_QUEUE, expected_count=1))
#   self.assertEquals([self.topic] * 2, [t['params']['topic'] for t in tasks])
#
  should "testNoSubscribers" do
    """Tests that when a feed has no subscribers we do not pull it."""
    Ohm.flush

    KnownFeed.create(:topic => @topic)

    assertTrue(!KnownFeed.get_by_key_name(KnownFeed.create_key(@topic).nil?))
    @entry_list = []
    FeedToFetch.insert([@topic])

    self.handle('post', {'topic' => @topic})

    # Verify that *no* feed entry records have been written.
    assertEquals([], FeedEntryRecord.get_entries_for_topic(@topic, @all_ids).to_a)

    # And any KnownFeeds were deleted.
    assertTrue(KnownFeed.get_by_key_name(KnownFeed.create_key(@topic)).nil?)

    # And there is no EventToDeliver or tasks.
    tasks = TaskQueue.all(EventToDeliver::EVENT_QUEUE)
    assert_equal 0, tasks.size

  end

  should "testRedirects" do
    """Tests when redirects are encountered."""
    info = FeedRecord.get_or_create(@topic)
    info.update(@headers)
    info.save
    FeedToFetch.insert([@topic])

    real_topic = 'http://example.com/real-topic-location'
    @headers['Location'] = real_topic

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '302', :headers => @headers, :body => @expected_response)
    Net::HTTP.any_instance.expects(:request).once.returns(@http_mock)

    @headers['Location'] = nil

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '200', :headers => @headers, :body => @expected_response)
    Net::HTTP.any_instance.expects(:request).once.returns(@http_mock)

    self.handle('post', {'topic' => @topic})

    assertTrue(!(EventToDeliver.all().first.nil?))

    tasks = TaskQueue.all(EventToDeliver::EVENT_QUEUE)
    assert_equal 1, tasks.size

  end

  should "testTooManyRedirects" do
    """Tests when too many redirects are encountered."""
    info = FeedRecord.get_or_create(@topic)
    info.update(@headers)
    info.save
    FeedToFetch.insert([@topic])

    last_topic = @topic
    real_topic = 'http://example.com/real-topic-location'

    (1..Main::MAX_REDIRECTS).each do |redirect|
      next_topic = real_topic + redirect.to_s
      @headers['Location'] = next_topic

      @http_mock = mock('Net::HTTPResponse')
      @http_mock.stubs(:code => '302', :headers => @headers, :body => @expected_response)
      Net::HTTP.any_instance.expects(:request).once.returns(@http_mock)

      last_topic = next_topic
    end

    self.handle('post', {'topic' => @topic})

    assertTrue(EventToDeliver.all.size == 0)

    tasks = TaskQueue.all(EventToDeliver::EVENT_QUEUE)
    assert_equal 0, tasks.size

    tasks = TaskQueue.all(FeedToFetch::FEED_QUEUE)
    assert_equal 1, tasks.size

    tasks = TaskQueue.all(FeedToFetch::FEED_RETRIES_QUEUE)
    assert_equal 1, tasks.size

  end

#
# def testPutSplitting(self):
#   """Tests that put() calls for feed records are split when too large."""
#   # Make the content way too big.
#   content_template = ('content' * 100 + '%s')
#   self.all_ids = [str(i) for i in xrange(1000)]
#   self.entry_payloads = [
#     (content_template % entry_id) for entry_id in self.all_ids
#   ]
#   self.entry_list = [
#       FeedEntryRecord.create_entry_for_topic(
#           self.topic, entry_id, 'content%s' % entry_id)
#       for entry_id in self.all_ids
#   ]
#
#   FeedToFetch.insert([self.topic])
#   urlfetch_test_stub.instance.expect(
#       'get', self.topic, 200, self.expected_response,
#       response_headers=self.headers)
#
#   old_max_new = main.MAX_NEW_FEED_ENTRY_RECORDS
#   main.MAX_NEW_FEED_ENTRY_RECORDS = len(self.all_ids) + 1
#   try:
#       self.handle('post', ('topic', self.topic))
#   finally:
#     main.MAX_NEW_FEED_ENTRY_RECORDS = old_max_new
#
#   # Verify that all feed entry records have been written along with the
#   # EventToDeliver and FeedRecord.
#   feed_entries = list(FeedEntryRecord.all())
#   self.assertEquals(set(self.all_ids), set(e.entry_id for e in feed_entries))
#
#   work = EventToDeliver.all().get()
#   event_key = work.key()
#   self.assertEquals(self.topic, work.topic)
#   self.assertTrue('\n'.join(self.entry_payloads) in work.payload)
#   work.delete()
#
#   record = FeedRecord.get_or_create(self.topic)
#   self.assertEquals(self.header_footer, record.header_footer)
#   self.assertEquals(self.etag, record.etag)
#   self.assertEquals(self.last_modified, record.last_modified)
#   self.assertEquals('application/atom+xml', record.content_type)
#
#   task = testutil.get_tasks(main.EVENT_QUEUE, index=0, expected_count=1)
#   self.assertEquals(str(event_key), task['params']['event_key'])
#   task = testutil.get_tasks(main.FEED_QUEUE, index=0, expected_count=1)
#   self.assertEquals(self.topic, task['params']['topic'])
#
# def testPutSplittingFails(self):
#   """Tests when splitting put() calls still doesn't help and we give up."""
#   # Make the content way too big.
#   content_template = ('content' * 100 + '%s')
#   self.all_ids = [str(i) for i in xrange(1000)]
#   self.entry_payloads = [
#     (content_template % entry_id) for entry_id in self.all_ids
#   ]
#   self.entry_list = [
#       FeedEntryRecord.create_entry_for_topic(
#           self.topic, entry_id, 'content%s' % entry_id)
#       for entry_id in self.all_ids
#   ]
#
#   FeedToFetch.insert([self.topic])
#   urlfetch_test_stub.instance.expect(
#       'get', self.topic, 200, self.expected_response,
#       response_headers=self.headers)
#
#   old_splitting_attempts = main.PUT_SPLITTING_ATTEMPTS
#   old_max_saves = main.MAX_FEED_RECORD_SAVES
#   old_max_new = main.MAX_NEW_FEED_ENTRY_RECORDS
#   main.PUT_SPLITTING_ATTEMPTS = 1
#   main.MAX_FEED_RECORD_SAVES = len(self.entry_list) + 1
#   main.MAX_NEW_FEED_ENTRY_RECORDS = main.MAX_FEED_RECORD_SAVES
#   try:
#     self.handle('post', ('topic', self.topic))
#   finally:
#     main.PUT_SPLITTING_ATTEMPTS = old_splitting_attempts
#     main.MAX_FEED_RECORD_SAVES = old_max_saves
#     main.MAX_NEW_FEED_ENTRY_RECORDS = old_max_new
#
#   # Verify that *NO* FeedEntryRecords or EventToDeliver has been written,
#   # the FeedRecord wasn't updated, and no tasks were enqueued.
#   self.assertEquals([], list(FeedEntryRecord.all()))
#   self.assertEquals(None, EventToDeliver.all().get())
#
#   record = FeedRecord.all().get()
#   self.assertNotEquals(self.etag, record.etag)
#
#   testutil.get_tasks(main.EVENT_QUEUE, expected_count=0)
#
# def testFeedTooLarge(self):
#   """Tests when the pulled feed's content size is too large."""
#   FeedToFetch.insert([self.topic])
#   urlfetch_test_stub.instance.expect(
#       'get', self.topic, 200, '',
#       response_headers=self.headers,
#       urlfetch_size_error=True)
#   self.handle('post', ('topic', self.topic))
#   self.assertEquals([], list(FeedEntryRecord.all()))
#   self.assertEquals(None, EventToDeliver.all().get())
#   testutil.get_tasks(main.EVENT_QUEUE, expected_count=0)
#
# def testTooManyNewEntries(self):
#   """Tests when there are more new entries than we can handle at once."""
#   self.all_ids = [str(i) for i in xrange(1000)]
#   self.entry_payloads = [
#     'content%s' % entry_id for entry_id in self.all_ids
#   ]
#   self.entry_list = [
#       FeedEntryRecord.create_entry_for_topic(
#           self.topic, entry_id, 'content%s' % entry_id)
#       for entry_id in self.all_ids
#   ]
#
#   FeedToFetch.insert([self.topic])
#   urlfetch_test_stub.instance.expect(
#       'get', self.topic, 200, self.expected_response,
#       response_headers=self.headers)
#
#   self.handle('post', ('topic', self.topic))
#
#   # Verify that a subset of the entry records are present and the payload
#   # only has the first N entries.
#   feed_entries = FeedEntryRecord.get_entries_for_topic(
#       self.topic, self.all_ids)
#   expected_records = main.MAX_NEW_FEED_ENTRY_RECORDS
#   self.assertEquals(self.all_ids[:expected_records],
#                     [e.entry_id for e in feed_entries])
#
#   work = EventToDeliver.all().get()
#   event_key = work.key()
#   self.assertEquals(self.topic, work.topic)
#   expected_content = '\n'.join(self.entry_payloads[:expected_records])
#   self.assertTrue(expected_content in work.payload)
#   self.assertFalse('content%d' % expected_records in work.payload)
#   work.delete()
#
#   record = FeedRecord.all().get()
#   self.assertNotEquals(self.etag, record.etag)
#
#   task = testutil.get_tasks(main.EVENT_QUEUE, index=0, expected_count=1)
#   self.assertEquals(str(event_key), task['params']['event_key'])
#   tasks = testutil.get_tasks(main.FEED_QUEUE, expected_count=1)
#   tasks.extend(testutil.get_tasks(main.FEED_RETRIES_QUEUE, expected_count=1))
#   for task in tasks:
#     self.assertEquals(self.topic, task['params']['topic'])

end
