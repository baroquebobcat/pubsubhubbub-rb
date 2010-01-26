require File.dirname(__FILE__) + '/../stories_helper'

class PushEventHandlerTest < Test::Unit::TestCase
  include Mocha::API

  def handle(method, options = {})
    post "/work/push_events", options
  end

  setup do
    Ohm.flush

    @chunk_size = EventToDeliver::EVENT_SUBSCRIBER_CHUNK_SIZE
    @topic = 'http://example.com/hamster-topic'

#    # Order of these URL fetches is determined by the ordering of the hashes
#    # of the callback URLs, so we need random extra strings here to get
#    # alphabetical hash order.
    @callback1 = 'http://example.com/hamster-callback1'
    @callback2 = 'http://example.com/hamster-callback2'
    @callback3 = 'http://example.com/hamster-callback3-12345'
    @callback4 = 'http://example.com/hamster-callback4-12345'
    @header_footer = '<feed>\n<stuff>blah</stuff>\n<xmldata/></feed>'
    @test_payloads = [
            '<entry>article1</entry>',
            '<entry>article2</entry>',
            '<entry>article3</entry>',
    ]
    @expected_payload = (
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<feed>\n'
    '<stuff>blah</stuff>\n'
    '<xmldata/>\n'
    '<entry>article1</entry>\n'
    '<entry>article2</entry>\n'
    '<entry>article3</entry>\n'
    '</feed>'
    )

    @header_footer_rss = '<rss><channel></channel></rss>'
    @test_payloads_rss = [
            '<item>article1</item>',
            '<item>article2</item>',
            '<item>article3</item>',
    ]
    @expected_payload_rss = (
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<rss><channel>\n'
    '<item>article1</item>\n'
    '<item>article2</item>\n'
    '<item>article3</item>\n'
    '</channel></rss>'
    )

    @bad_key = 'does_not_exist' #db.Key.from_path(EventToDeliver.kind(), 'does_not_exist')

  end

  should "testNoWork" do
    self.handle('post', {'event_key' => @bad_key})
  end

  should "testNoExtraSubscribers" do
    """Tests when a single chunk of delivery is enough."""
    assertTrue(Subscription.insert(
            @callback1, @topic, 'token', 'secret'))
    assertTrue(Subscription.insert(
            @callback2, @topic, 'token', 'secret'))
    assertTrue(Subscription.insert(
            @callback3, @topic, 'token', 'secret'))

    Main::EVENT_SUBSCRIBER_CHUNK_SIZE = 3

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '204', :headers => @headers, :body => '')
    Net::HTTP.any_instance.expects(:request).once.returns(@http_mock)

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '200', :headers => @headers, :body => '')
    Net::HTTP.any_instance.expects(:request).once.returns(@http_mock)

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '204', :headers => @headers, :body => '')
    Net::HTTP.any_instance.expects(:request).once.returns(@http_mock)

    event = EventToDeliver.create_event_for_topic(
            @topic, EventToDeliver::ATOM, @header_footer, @test_payloads)

    Net::HTTP::Post.any_instance.expects(:initialize).at_least_once


    self.handle('post', {'event_key' => event.key_name})
    assertEquals([], EventToDeliver.all().to_a)

    tasks = TaskQueue.all(EventToDeliver::EVENT_QUEUE)
    assert_equal 0, tasks.size
  end

  should "testHmacData" do
    """Tests that the content is properly signed with an HMAC."""
    assertTrue(Subscription.insert(
            @callback1, @topic, 'token', 'secret3'))
    # Secret is empty on purpose here, so the verify_token will be used instead.
    assertTrue(Subscription.insert(
            @callback2, @topic, 'my-token', ''))
    assertTrue(Subscription.insert(
            @callback3, @topic, 'token', 'secret-stuff'))

    Net::HTTP::Post.any_instance.expects(:initialize).with(URI(@callback1).path, {
            'X-Hub-Signature'=> 'sha1=39393b224c7f4ce57bb0ab2fad1cfacbfe62d643',
            'Content-Type'=> 'application/atom+xml'}).once

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '204', :headers => @headers, :body => '')
    Net::HTTP.any_instance.expects(:request).once.returns(@http_mock)

    Net::HTTP::Post.any_instance.expects(:initialize).with(URI(@callback2).path, {
            'Content-Type'=> 'application/atom+xml',
            'X-Hub-Signature'=> 'sha1=cc40289c73b1672154843dc3630fe028fa17789d'}).once

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '200', :headers => @headers, :body => '')
    Net::HTTP.any_instance.expects(:request).once.returns(@http_mock)

    Net::HTTP::Post.any_instance.expects(:initialize).with(URI(@callback3).path, {
            'Content-Type'=> 'application/atom+xml',
            'X-Hub-Signature'=> 'sha1=b738e186842032b184a591464622d6e474fc5490'}).once

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '204', :headers => @headers, :body => '')
    Net::HTTP.any_instance.expects(:request).once.returns(@http_mock)

    event = EventToDeliver.create_event_for_topic(
            @topic, EventToDeliver::ATOM, @header_footer, @test_payloads)

    self.handle('post', {'event_key' => event.key_name})

    assertEquals([], EventToDeliver.all().to_a)

    tasks = TaskQueue.all(EventToDeliver::EVENT_QUEUE)
    assert_equal 0, tasks.size
  end


  should "testRssContentType" do
    """Tests that the content type of an RSS feed is properly supplied."""
    assertTrue(Subscription.insert(
            @callback1, @topic, 'token', 'secret'))

    expectation = Net::HTTP::Post.any_instance.expects(:initialize).with(URI(@callback1).path, {
            'X-Hub-Signature'=> 'sha1=d93d3a694abebc35df6612ef9f2503a3f54f77e0',
            'Content-Type'=> 'application/rss+xml'}).once

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '204', :headers => @headers, :body => '')
    Net::HTTP.any_instance.expects(:request).once.returns(@http_mock)

    event = EventToDeliver.create_event_for_topic(
            @topic, EventToDeliver::RSS, @header_footer_rss, @test_payloads_rss)
    self.handle('post', {'event_key' => event.key_name})
    assertEquals([], EventToDeliver.all().to_a)
    tasks = TaskQueue.all(EventToDeliver::EVENT_QUEUE)
    assert_equal 0, tasks.size

    assert expectation.verified?
  end

#
#  def testExtraSubscribers(self):
#    """Tests when there are more subscribers to contact after delivery."""
#    self.assertTrue(Subscription.insert(
#        self.callback1, self.topic, 'token', 'secret'))
#    self.assertTrue(Subscription.insert(
#        self.callback2, self.topic, 'token', 'secret'))
#    self.assertTrue(Subscription.insert(
#        self.callback3, self.topic, 'token', 'secret'))
#    main.EVENT_SUBSCRIBER_CHUNK_SIZE = 1
#    event = EventToDeliver.create_event_for_topic(
#        self.topic, main.ATOM, self.header_footer, self.test_payloads)
#    event.put()
#    event_key = str(event.key())
#
#    urlfetch_test_stub.instance.expect(
#        'post', self.callback1, 204, '', request_payload=self.expected_payload)
#    self.handle('post', ('event_key', event_key))
#    urlfetch_test_stub.instance.verify_and_reset()
#
#    urlfetch_test_stub.instance.expect(
#        'post', self.callback2, 200, '', request_payload=self.expected_payload)
#    self.handle('post', ('event_key', event_key))
#    urlfetch_test_stub.instance.verify_and_reset()
#
#    urlfetch_test_stub.instance.expect(
#        'post', self.callback3, 204, '', request_payload=self.expected_payload)
#    self.handle('post', ('event_key', event_key))
#    urlfetch_test_stub.instance.verify_and_reset()
#    self.assertEquals([], list(EventToDeliver.all()))
#
#    tasks = testutil.get_tasks(main.EVENT_QUEUE, expected_count=2)
#    self.assertEquals([event_key] * 2,
#                      [t['params']['event_key'] for t in tasks])
#
#  def testBrokenCallbacks(self):
#    """Tests that when callbacks return errors and are saved for later."""
#    self.assertTrue(Subscription.insert(
#        self.callback1, self.topic, 'token', 'secret'))
#    self.assertTrue(Subscription.insert(
#        self.callback2, self.topic, 'token', 'secret'))
#    self.assertTrue(Subscription.insert(
#        self.callback3, self.topic, 'token', 'secret'))
#    main.EVENT_SUBSCRIBER_CHUNK_SIZE = 2
#    event = EventToDeliver.create_event_for_topic(
#        self.topic, main.ATOM, self.header_footer, self.test_payloads)
#    event.put()
#    event_key = str(event.key())
#
#    urlfetch_test_stub.instance.expect(
#        'post', self.callback1, 302, '', request_payload=self.expected_payload)
#    urlfetch_test_stub.instance.expect(
#        'post', self.callback2, 404, '', request_payload=self.expected_payload)
#    self.handle('post', ('event_key', event_key))
#    urlfetch_test_stub.instance.verify_and_reset()
#
#    urlfetch_test_stub.instance.expect(
#        'post', self.callback3, 500, '', request_payload=self.expected_payload)
#    self.handle('post', ('event_key', event_key))
#    urlfetch_test_stub.instance.verify_and_reset()
#
#    work = EventToDeliver.all().get()
#    sub_list = Subscription.get(work.failed_callbacks)
#    callback_list = [sub.callback for sub in sub_list]
#    self.assertEquals([self.callback1, self.callback2, self.callback3],
#                      callback_list)
#
#    tasks = testutil.get_tasks(main.EVENT_QUEUE, expected_count=1)
#    tasks.extend(testutil.get_tasks(main.EVENT_RETRIES_QUEUE, expected_count=1))
#    self.assertEquals([event_key] * 2,
#                      [t['params']['event_key'] for t in tasks])
#
#  def testDeadlineError(self):
#    """Tests that callbacks in flight at deadline will be marked as failed."""
#    try:
#      def deadline():
#        raise runtime.DeadlineExceededError()
#      main.async_proxy.wait = deadline
#
#      self.assertTrue(Subscription.insert(
#          self.callback1, self.topic, 'token', 'secret'))
#      self.assertTrue(Subscription.insert(
#          self.callback2, self.topic, 'token', 'secret'))
#      self.assertTrue(Subscription.insert(
#          self.callback3, self.topic, 'token', 'secret'))
#      main.EVENT_SUBSCRIBER_CHUNK_SIZE = 2
#      event = EventToDeliver.create_event_for_topic(
#          self.topic, main.ATOM, self.header_footer, self.test_payloads)
#      event.put()
#      event_key = str(event.key())
#      self.handle('post', ('event_key', event_key))
#
#      # All events should be marked as failed even though no urlfetches
#      # were made.
#      work = EventToDeliver.all().get()
#      sub_list = Subscription.get(work.failed_callbacks)
#      callback_list = [sub.callback for sub in sub_list]
#      self.assertEquals([self.callback1, self.callback2], callback_list)
#
#      self.assertEquals(event_key, testutil.get_tasks(
#          main.EVENT_QUEUE, index=0, expected_count=1)['params']['event_key'])
#    finally:
#      main.async_proxy = async_apiproxy.AsyncAPIProxy()
#
#  def testRetryLogic(self):
#    """Tests that failed urls will be retried after subsequent failures.
#
#    This is an end-to-end test for push delivery failures and retries. We'll
#    simulate multiple times through the failure list.
#    """
#    self.assertTrue(Subscription.insert(
#        self.callback1, self.topic, 'token', 'secret'))
#    self.assertTrue(Subscription.insert(
#        self.callback2, self.topic, 'token', 'secret'))
#    self.assertTrue(Subscription.insert(
#        self.callback3, self.topic, 'token', 'secret'))
#    self.assertTrue(Subscription.insert(
#        self.callback4, self.topic, 'token', 'secret'))
#    main.EVENT_SUBSCRIBER_CHUNK_SIZE = 3
#    event = EventToDeliver.create_event_for_topic(
#        self.topic, main.ATOM, self.header_footer, self.test_payloads)
#    event.put()
#    event_key = str(event.key())
#
#    # First pass through all URLs goes full speed for two chunks.
#    urlfetch_test_stub.instance.expect(
#        'post', self.callback1, 404, '', request_payload=self.expected_payload)
#    urlfetch_test_stub.instance.expect(
#        'post', self.callback2, 204, '', request_payload=self.expected_payload)
#    urlfetch_test_stub.instance.expect(
#        'post', self.callback3, 302, '', request_payload=self.expected_payload)
#    self.handle('post', ('event_key', event_key))
#    urlfetch_test_stub.instance.verify_and_reset()
#
#    urlfetch_test_stub.instance.expect(
#        'post', self.callback4, 500, '', request_payload=self.expected_payload)
#    self.handle('post', ('event_key', event_key))
#    urlfetch_test_stub.instance.verify_and_reset()
#
#    # Now the retries.
#    urlfetch_test_stub.instance.expect(
#        'post', self.callback1, 404, '', request_payload=self.expected_payload)
#    urlfetch_test_stub.instance.expect(
#        'post', self.callback3, 302, '', request_payload=self.expected_payload)
#    urlfetch_test_stub.instance.expect(
#        'post', self.callback4, 500, '', request_payload=self.expected_payload)
#    self.handle('post', ('event_key', event_key))
#    urlfetch_test_stub.instance.verify_and_reset()
#
#    urlfetch_test_stub.instance.expect(
#        'post', self.callback1, 204, '', request_payload=self.expected_payload)
#    urlfetch_test_stub.instance.expect(
#        'post', self.callback3, 302, '', request_payload=self.expected_payload)
#    urlfetch_test_stub.instance.expect(
#        'post', self.callback4, 200, '', request_payload=self.expected_payload)
#    self.handle('post', ('event_key', event_key))
#    urlfetch_test_stub.instance.verify_and_reset()
#
#    urlfetch_test_stub.instance.expect(
#        'post', self.callback3, 204, '', request_payload=self.expected_payload)
#    self.handle('post', ('event_key', event_key))
#    urlfetch_test_stub.instance.verify_and_reset()
#
#    self.assertEquals([], list(EventToDeliver.all()))
#    tasks = testutil.get_tasks(main.EVENT_QUEUE, expected_count=1)
#    tasks.extend(testutil.get_tasks(main.EVENT_RETRIES_QUEUE, expected_count=3))
#    self.assertEquals([event_key] * 4,
#                      [t['params']['event_key'] for t in tasks])
#
#  def testUrlFetchFailure(self):
#    """Tests the UrlFetch API raising exceptions while sending notifications."""
#    self.assertTrue(Subscription.insert(
#        self.callback1, self.topic, 'token', 'secret'))
#    self.assertTrue(Subscription.insert(
#        self.callback2, self.topic, 'token', 'secret'))
#    main.EVENT_SUBSCRIBER_CHUNK_SIZE = 3
#    event = EventToDeliver.create_event_for_topic(
#        self.topic, main.ATOM, self.header_footer, self.test_payloads)
#    event.put()
#    event_key = str(event.key())
#
#    urlfetch_test_stub.instance.expect(
#        'post', self.callback1, 200, '',
#        request_payload=self.expected_payload, urlfetch_error=True)
#    urlfetch_test_stub.instance.expect(
#        'post', self.callback2, 200, '',
#        request_payload=self.expected_payload, apiproxy_error=True)
#    self.handle('post', ('event_key', event_key))
#    urlfetch_test_stub.instance.verify_and_reset()
#
#    work = EventToDeliver.all().get()
#    sub_list = Subscription.get(work.failed_callbacks)
#    callback_list = [sub.callback for sub in sub_list]
#    self.assertEquals([self.callback1, self.callback2], callback_list)
#
#    self.assertEquals(event_key, testutil.get_tasks(
#        main.EVENT_RETRIES_QUEUE, index=0, expected_count=1)
#        ['params']['event_key'])
#
#
end
