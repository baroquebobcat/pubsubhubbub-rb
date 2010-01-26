require "stories_helper"

class SubscribeHandlerTest < Test::Unit::TestCase
  include Mocha::API

  FUNNY = '/CaSeSeNsItIvE'

  def handle(method, options = {})
    if method.eql? 'get'
      get "/subscribe"
    else
      post "/subscribe", options
    end
  end

  setup do
    Ohm.flush

    @callback = 'http://localhost/good-callback'
    @topic = 'http://localhost/the-topic'
    @verify_token = 'the_token'

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '200', :body => 'this_is_my_fake_challenge_string')
    Net::HTTP.any_instance.expects(:request).at_least_once.returns(@http_mock)
  end

  def verify_callback_querystring_template(value)
    @callback +
            "?hub.verify_token=the_token"+
            "&hub.challenge=this_is_my_fake_challenge_string"+
            "&hub.topic=http%%3A%%2F%%2Fexample.com%%2Fthe-topic"+
            "&hub.mode=#{value}"+
            "&hub.lease_seconds=2592000"
  end

  def verify_record_task(topic, options = {})
    """Tests there is a valid KnownFeedIdentity task enqueued.

    Args:
      topic: The topic the task should be for.

    Raises:
      AssertionError if the task isn't there.
    """
    tasks = TaskQueue.all(KnownFeed::MAPPINGS_QUEUE)
    assert_equal options[:expected_count], tasks.size
    task = tasks[options[:index]]
    assertEquals(topic, task.params['topic'])
  end

  should "testDebugFormRenders" do
    handle('get')
    assertTrue(response_body().include? '<html>')
  end

  should "testValidation" do
    """Tests form validation."""
    # Bad mode
    handle('post',
           {'hub.mode'=> 'bad',
            'hub.callback'=> @callback,
            'hub.topic'=> @topic,
            'hub.verify'=> 'async',
            'hub.verify_token'=> @verify_token})
    self.assertEquals(400, self.response_code())
    self.assertTrue(response_body().include? 'hub.mode' )

    # Empty callback
    self.handle('post',
                {'hub.mode' => 'subscribe',
                 'hub.callback'=> '',
                 'hub.topic'=> @topic,
                 'hub.verify'=> 'async',
                 'hub.verify_token'=> @verify_token})
    self.assertEquals(400, self.response_code())
    self.assertTrue(self.response_body().include? 'hub.callback')


    # Bad callback URL
    self.handle('post',
                {'hub.mode' => 'subscribe',
                 'hub.callback' => 'httpf://example.com',
                 'hub.topic' => @topic,
                 'hub.verify' => 'async',
                 'hub.verify_token' => @verify_token})
    self.assertEquals(400, self.response_code())
    self.assertTrue(self.response_body().include? 'hub.callback')

    # Empty topic
    self.handle('post',
                {'hub.mode' => 'subscribe',
                 'hub.callback' => @callback,
                 'hub.topic' => '',
                 'hub.verify' => 'async',
                 'hub.verify_token' => @verify_token})
    self.assertEquals(400, self.response_code())
    self.assertTrue(self.response_body().include? 'hub.topic')

    # Bad topic URL
    self.handle('post',
                {'hub.mode' => 'subscribe',
                 'hub.callback' => @callback,
                 'hub.topic' => 'httpf://example.com',
                 'hub.verify' => 'async',
                 'hub.verify_token' => @verify_token})
    self.assertEquals(400, self.response_code())
    self.assertTrue(self.response_body().include? 'hub.topic')

    # Bad verify
    self.handle('post',
                {'hub.mode' => 'subscribe',
                 'hub.callback' => @callback,
                 'hub.topic' => @topic,
                 'hub.verify' => 'meep',
                 'hub.verify_token' => @verify_token})
    self.assertEquals(400, self.response_code())
    self.assertTrue(self.response_body().include? 'hub.verify')

    # Bad lease_seconds
    self.handle('post',
                {'hub.mode' => 'subscribe',
                 'hub.callback' => @callback,
                 'hub.topic' => @topic,
                 'hub.verify' => 'async',
                 'hub.verify_token' => 'asdf',
                 'hub.lease_seconds' => 'stuff'})
    self.assertEquals(400, self.response_code())
    self.assertTrue(self.response_body().include? 'hub.lease_seconds')

    # Bad lease_seconds zero padding will break things
    self.handle('post',
                {'hub.mode' => 'subscribe',
                 'hub.callback' => @callback,
                 'hub.topic' => @topic,
                 'hub.verify' => 'async',
                 'hub.verify_token' => 'asdf',
                 'hub.lease_seconds' => '000010'})
    self.assertEquals(400, self.response_code())
    self.assertTrue(self.response_body().include? 'hub.lease_seconds')

  end

  should "testUnsubscribeMissingSubscription" do
    """Tests that deleting a non-existent subscription does nothing."""
    self.handle('post',
                {'hub.callback' => @callback,
                 'hub.topic' => @topic,
                 'hub.verify' => 'sync',
                 'hub.mode' => 'unsubscribe',
                 'hub.verify_token' => @verify_token})
    self.assertEquals(204, self.response_code())
  end

  should "testSynchronous" do
    """Tests synchronous subscribe and unsubscribe."""
    sub_key = Subscription.create_key_name(@callback, @topic)
    self.assertTrue(Subscription.get_by_key_name(sub_key).nil?)

    self.handle('post',
                {'hub.callback' => @callback,
                 'hub.topic' => @topic,
                 'hub.mode' => 'subscribe',
                 'hub.verify' => 'sync',
                 'hub.verify_token' => @verify_token})


    self.assertEquals(204, self.response_code())
    sub = Subscription.get_by_key_name(sub_key)
    self.assertTrue(!sub.nil?)
    self.assertEquals(Subscription::STATE_VERIFIED, sub.subscription_state)
    self.verify_record_task(@topic, :expected_count=>1, :index=>0)

    self.handle('post',
                {'hub.callback' => @callback,
                 'hub.topic' => @topic,
                 'hub.mode' => 'unsubscribe',
                 'hub.verify' => 'sync',
                 'hub.verify_token' => @verify_token})
    self.assertEquals(204, self.response_code())
    self.assertTrue(Subscription.get_by_key_name(sub_key).nil?)

    assert 0, Subscription.all.size
  end

  should "testAsynchronous" do
    """Tests sync and async subscriptions cause the correct state transitions.

    Also tests that synchronous subscribes and unsubscribes will overwrite
    asynchronous requests.
    """
    sub_key = Subscription.create_key_name(@callback, @topic)
    self.assertTrue(Subscription.get_by_key_name(sub_key).nil?)

    # Async subscription.
    self.handle('post',
                {'hub.callback' => @callback,
                 'hub.topic' => @topic,
                 'hub.mode' => 'subscribe',
                 'hub.verify' => 'async',
                 'hub.verify_token' => @verify_token})
    self.assertEquals(202, self.response_code())
    sub = Subscription.get_by_key_name(sub_key)
    self.assertTrue(!sub.nil?)
    self.assertEquals(Subscription::STATE_NOT_VERIFIED, sub.subscription_state)

    # Sync subscription overwrites.
    self.handle('post',
                {'hub.callback' => @callback,
                 'hub.topic' => @topic,
                 'hub.mode' => 'subscribe',
                 'hub.verify' => 'sync',
                 'hub.verify_token' => @verify_token})
    self.assertEquals(204, self.response_code())
    sub = Subscription.get_by_key_name(sub_key)
    self.assertTrue(!sub.nil?)
    self.assertEquals(Subscription::STATE_VERIFIED, sub.subscription_state)
    self.verify_record_task(@topic, :expected_count=>1, :index=>0)

    # Async unsubscribe queues removal, but does not change former state.
    self.handle('post',
                {'hub.callback' => @callback,
                 'hub.topic' => @topic,
                 'hub.mode' => 'unsubscribe',
                 'hub.verify' => 'async',
                 'hub.verify_token' => @verify_token})
    self.assertEquals(202, self.response_code())
    sub = Subscription.get_by_key_name(sub_key)
    self.assertTrue(!sub.nil?)
    self.assertEquals(Subscription::STATE_VERIFIED, sub.subscription_state)

    # Synch unsubscribe overwrites.
    self.handle('post',
                {'hub.callback' => @callback,
                 'hub.topic' => @topic,
                 'hub.mode' => 'unsubscribe',
                 'hub.verify' => 'sync',
                 'hub.verify_token' => @verify_token})
    self.assertEquals(204, self.response_code())
    self.assertTrue(Subscription.get_by_key_name(sub_key).nil?)

  end

  should "testResubscribe" do
    """Tests that subscribe requests will reset pending unsubscribes."""
    sub_key = Subscription.create_key_name(@callback, @topic)
    self.assertTrue(Subscription.get_by_key_name(sub_key).nil?)

    # Async subscription.
    self.handle('post',
                {'hub.callback' => @callback,
                 'hub.topic' => @topic,
                 'hub.mode' => 'subscribe',
                 'hub.verify' => 'async',
                 'hub.verify_token' => @verify_token})
    self.assertEquals(202, self.response_code())
    sub = Subscription.get_by_key_name(sub_key)
    self.assertTrue(!sub.nil?)
    self.assertEquals(Subscription::STATE_NOT_VERIFIED, sub.subscription_state)

    # Async un-subscription does not change previous subscription state.
    self.handle('post',
                {'hub.callback' => @callback,
                 'hub.topic' => @topic,
                 'hub.mode' => 'unsubscribe',
                 'hub.verify' => 'async',
                 'hub.verify_token' => @verify_token})
    self.assertEquals(202, self.response_code())
    sub = Subscription.get_by_key_name(sub_key)
    self.assertTrue(!sub.nil?)
    self.assertEquals(Subscription::STATE_NOT_VERIFIED, sub.subscription_state)

    # Synchronous subscription overwrites.
    self.handle('post',
                {'hub.callback' => @callback,
                 'hub.topic' => @topic,
                 'hub.mode' => 'subscribe',
                 'hub.verify' => 'sync',
                 'hub.verify_token' => @verify_token})
    self.assertEquals(204, self.response_code())
    sub = Subscription.get_by_key_name(sub_key)
    self.assertTrue(!sub.nil?)
    self.assertEquals(Subscription::STATE_VERIFIED, sub.subscription_state)
    self.verify_record_task(@topic, :expected_count=>1, :index=>0)

  end

  should "testMaxLeaseSeconds" do
    """Tests when the max lease period is specified."""
    sub_key = Subscription.create_key_name(@callback, @topic)
    self.assertTrue(Subscription.get_by_key_name(sub_key).nil?)

#    self.verify_callback_querystring_template = (
#        self.callback +
#        '?hub.verify_token=the_token'
#        '&hub.challenge=this_is_my_fake_challenge_string'
#        '&hub.topic=http%%3A%%2F%%2Fexample.com%%2Fthe-topic'
#        '&hub.mode=%s'
#        '&hub.lease_seconds=7776000')
#
#    urlfetch_test_stub.instance.expect(
#        'get', self.verify_callback_querystring_template % 'subscribe', 200,
#        self.challenge)
#
    self.handle('post',
                {'hub.callback' => @callback,
                 'hub.topic' => @topic,
                 'hub.mode' => 'subscribe',
                 'hub.verify' => 'sync',
                 'hub.verify_token' => @verify_token,
                 'hub.lease_seconds' => '1000000000000000000'})
    self.assertEquals(204, self.response_code())
    sub = Subscription.get_by_key_name(sub_key)
    self.assertTrue(!sub.nil?)
    self.assertEquals(Subscription::STATE_VERIFIED, sub.subscription_state)
    self.verify_record_task(@topic, :expected_count=>1, :index=>0)
  end

  should "testInvalidChallenge" do
    """Tests when the returned challenge is bad."""
    sub_key = Subscription.create_key_name(@callback, @topic)
    self.assertTrue(Subscription.get_by_key_name(sub_key).nil?)

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '200', :body => 'bad')
    Net::HTTP.any_instance.expects(:request).at_least_once.returns(@http_mock)

    self.handle('post',
                {'hub.callback' => @callback,
                 'hub.topic' => @topic,
                 'hub.mode' => 'subscribe',
                 'hub.verify' => 'sync',
                 'hub.verify_token' => @verify_token})
    self.assertTrue(Subscription.get_by_key_name(sub_key).nil?)
    self.assertTrue(KnownFeed.find(:key_name => KnownFeed.create_key(@topic).first.nil?))
    self.assertEquals(409, self.response_code())

  end

  should "testSynchronousConfirmFailure" do
    """Tests when synchronous confirmations fail."""
    # Subscribe
    sub_key = Subscription.create_key_name(@callback, @topic)
    self.assertTrue(Subscription.get_by_key_name(sub_key).nil?)

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '500', :body => '')
    Net::HTTP.any_instance.expects(:request).at_least_once.returns(@http_mock)

    self.handle('post',
                {'hub.callback' => @callback,
                 'hub.topic' => @topic,
                 'hub.mode' => 'subscribe',
                 'hub.verify' => 'sync',
                 'hub.verify_token' => @verify_token})
    self.assertTrue(Subscription.get_by_key_name(sub_key).nil?)
    self.assertTrue(KnownFeed.find(:key_name => KnownFeed.create_key(@topic)).first.nil?)
    self.assertEquals(409, self.response_code())

    # Unsubscribe
    Subscription.insert(@callback, @topic, @verify_token, 'secret')

    self.handle('post',
                {'hub.callback' => @callback,
                 'hub.topic' => @topic,
                 'hub.mode' => 'unsubscribe',
                 'hub.verify' => 'sync',
                 'hub.verify_token' => @verify_token})
    self.assertTrue(!Subscription.get_by_key_name(sub_key).nil?)
    self.assertEquals(409, self.response_code())

  end

#  def testAfterSubscriptionError(self):
#    """Tests when an exception occurs after subscription."""
#    for exception in (runtime.DeadlineExceededError(), db.Error(),
#                      apiproxy_errors.Error()):
#      def new_confirm(*args):
#        raise exception
#      main.hooks.override_for_test(main.confirm_subscription, new_confirm)
#      try:
#        self.handle('post',
#            ('hub.callback', self.callback),
#            ('hub.topic', self.topic),
#            ('hub.mode', 'subscribe'),
#            ('hub.verify', 'sync'),
#            ('hub.verify_token', self.verify_token))
#        self.assertEquals(503, self.response_code())
#      finally:
#        main.hooks.reset_for_test(main.confirm_subscription)
#
#  def testSubscriptionError(self):
#    """Tests when errors occurs during subscription."""
#    # URLFetch errors are probably the subscriber's fault, so we'll serve these
#    # as a conflict.
#    urlfetch_test_stub.instance.expect(
#        'get', self.verify_callback_querystring_template % 'subscribe',
#        None, '', urlfetch_error=True)
#    self.handle('post',
#        ('hub.callback', self.callback),
#        ('hub.topic', self.topic),
#        ('hub.mode', 'subscribe'),
#        ('hub.verify', 'sync'),
#        ('hub.verify_token', self.verify_token))
#    self.assertEquals(409, self.response_code())
#
#    # An apiproxy error or deadline error will fall through and serve a 503,
#    # since that means there's something wrong with our service.
#    urlfetch_test_stub.instance.expect(
#        'get', self.verify_callback_querystring_template % 'subscribe',
#        None, '', apiproxy_error=True)
#    self.handle('post',
#        ('hub.callback', self.callback),
#        ('hub.topic', self.topic),
#        ('hub.mode', 'subscribe'),
#        ('hub.verify', 'sync'),
#        ('hub.verify_token', self.verify_token))
#    self.assertEquals(503, self.response_code())
#
#    urlfetch_test_stub.instance.expect(
#        'get', self.verify_callback_querystring_template % 'subscribe',
#        None, '', deadline_error=True)
#    self.handle('post',
#        ('hub.callback', self.callback),
#        ('hub.topic', self.topic),
#        ('hub.mode', 'subscribe'),
#        ('hub.verify', 'sync'),
#        ('hub.verify_token', self.verify_token))
#    self.assertEquals(503, self.response_code())
#

  should "testCaseSensitive" do
    """Tests that the case of topics, callbacks, and tokens are preserved."""
    @topic += FUNNY
    @callback += FUNNY
    @verify_token += FUNNY
    sub_key = Subscription.create_key_name(@callback, @topic)
    self.assertTrue(Subscription.get_by_key_name(sub_key).nil?)

    self.handle('post',
                {'hub.callback' => @callback,
                 'hub.topic' => @topic,
                 'hub.mode' => 'subscribe',
                 'hub.verify' => 'sync',
                 'hub.verify_token' => @verify_token})
    self.assertEquals(204, self.response_code())
    sub = Subscription.get_by_key_name(sub_key)
    self.assertTrue(!sub.nil?)
    self.assertEquals(Subscription::STATE_VERIFIED, sub.subscription_state)
    self.verify_record_task(@topic, :expected_count=>1, :index=>0)
  end

#  def testSubscribeNormalization(self):
#    """Tests that the topic and callback URLs are properly normalized."""
#    self.topic += OTHER_STRING
#    orig_callback = self.callback
#    self.callback += OTHER_STRING
#    sub_key = Subscription.create_key_name(
#        main.normalize_iri(self.callback),
#        main.normalize_iri(self.topic))
#    self.assertTrue(Subscription.get_by_key_name(sub_key) is None)
#    self.verify_callback_querystring_template = (
#        orig_callback + '/~one:two/&='
#        '?hub.verify_token=the_token'
#        '&hub.challenge=this_is_my_fake_challenge_string'
#        '&hub.topic=http%%3A%%2F%%2Fexample.com%%2Fthe-topic'
#          '%%2F%%7Eone%%3Atwo%%2F%%26%%3D'
#        '&hub.mode=%s'
#        '&hub.lease_seconds=2592000')
#    urlfetch_test_stub.instance.expect(
#        'get', self.verify_callback_querystring_template % 'subscribe', 200,
#        self.challenge)
#
#    self.handle('post',
#        ('hub.callback', self.callback),
#        ('hub.topic', self.topic),
#        ('hub.mode', 'subscribe'),
#        ('hub.verify', 'sync'),
#        ('hub.verify_token', self.verify_token))
#    self.assertEquals(204, self.response_code())
#    sub = Subscription.get_by_key_name(sub_key)
#    self.assertTrue(sub is not None)
#    self.assertEquals(Subscription.STATE_VERIFIED, sub.subscription_state)
#    self.verify_record_task(main.normalize_iri(self.topic))
#
#  def testSubscribeIri(self):
#    """Tests when the topic, callback, verify_token, and secrets are IRIs."""
#    topic = self.topic + FUNNY_UNICODE
#    topic_utf8 = self.topic + FUNNY_UTF8
#    callback = self.callback + FUNNY_UNICODE
#    callback_utf8 = self.callback + FUNNY_UTF8
#    verify_token = self.verify_token + FUNNY_UNICODE
#    verify_token_utf8 = self.verify_token + FUNNY_UTF8
#
#    sub_key = Subscription.create_key_name(
#        main.normalize_iri(callback),
#        main.normalize_iri(topic))
#    self.assertTrue(Subscription.get_by_key_name(sub_key) is None)
#    self.verify_callback_querystring_template = (
#        self.callback +
#            '/blah/%%E3%%83%%96%%E3%%83%%AD%%E3%%82%%B0%%E8%%A1%%86'
#        '?hub.verify_token=the_token%%2F'
#            'blah%%2F%%E3%%83%%96%%E3%%83%%AD%%E3%%82%%B0%%E8%%A1%%86'
#        '&hub.challenge=this_is_my_fake_challenge_string'
#        '&hub.topic=http%%3A%%2F%%2Fexample.com%%2Fthe-topic%%2F'
#            'blah%%2F%%25E3%%2583%%2596%%25E3%%2583%%25AD'
#            '%%25E3%%2582%%25B0%%25E8%%25A1%%2586'
#        '&hub.mode=%s'
#        '&hub.lease_seconds=2592000')
#    urlfetch_test_stub.instance.expect(
#        'get', self.verify_callback_querystring_template % 'subscribe', 200,
#        self.challenge)
#
#    self.handle('post',
#        ('hub.callback', callback_utf8),
#        ('hub.topic', topic_utf8),
#        ('hub.mode', 'subscribe'),
#        ('hub.verify', 'sync'),
#        ('hub.verify_token', verify_token_utf8))
#    self.assertEquals(204, self.response_code())
#    sub = Subscription.get_by_key_name(sub_key)
#    self.assertTrue(sub is not None)
#    self.assertEquals(Subscription.STATE_VERIFIED, sub.subscription_state)
#    self.verify_record_task(self.topic + FUNNY_IRI)
#
#  def testSubscribeUnicode(self):
#    """Tests when UTF-8 encoded bytes show up in the requests.
#
#    Technically this isn't well-formed or allowed by the HTTP/URI spec, but
#    people do it anyways and we may as well allow it.
#    """
#    quoted_topic = urllib.quote(self.topic)
#    topic = self.topic + FUNNY_UNICODE
#    topic_utf8 = self.topic + FUNNY_UTF8
#    quoted_callback = urllib.quote(self.callback)
#    callback = self.callback + FUNNY_UNICODE
#    callback_utf8 = self.callback + FUNNY_UTF8
#    quoted_verify_token = urllib.quote(self.verify_token)
#    verify_token = self.verify_token + FUNNY_UNICODE
#    verify_token_utf8 = self.verify_token + FUNNY_UTF8
#
#    sub_key = Subscription.create_key_name(
#        main.normalize_iri(callback),
#        main.normalize_iri(topic))
#    self.assertTrue(Subscription.get_by_key_name(sub_key) is None)
#    self.verify_callback_querystring_template = (
#        self.callback +
#            '/blah/%%E3%%83%%96%%E3%%83%%AD%%E3%%82%%B0%%E8%%A1%%86'
#        '?hub.verify_token=the_token%%2F'
#            'blah%%2F%%E3%%83%%96%%E3%%83%%AD%%E3%%82%%B0%%E8%%A1%%86'
#        '&hub.challenge=this_is_my_fake_challenge_string'
#        '&hub.topic=http%%3A%%2F%%2Fexample.com%%2Fthe-topic%%2F'
#            'blah%%2F%%25E3%%2583%%2596%%25E3%%2583%%25AD'
#            '%%25E3%%2582%%25B0%%25E8%%25A1%%2586'
#        '&hub.mode=%s'
#        '&hub.lease_seconds=2592000')
#    urlfetch_test_stub.instance.expect(
#        'get', self.verify_callback_querystring_template % 'subscribe', 200,
#        self.challenge)
#
#    payload = (
#        'hub.callback=' + quoted_callback + FUNNY_UTF8 +
#        '&hub.topic=' + quoted_topic + FUNNY_UTF8 +
#        '&hub.mode=subscribe'
#        '&hub.verify=sync'
#        '&hub.verify_token=' + quoted_verify_token + FUNNY_UTF8)
#
#    self.handle_body('post', payload)
#    self.assertEquals(204, self.response_code())
#    sub = Subscription.get_by_key_name(sub_key)
#    self.assertTrue(sub is not None)
#    self.assertEquals(Subscription.STATE_VERIFIED, sub.subscription_state)
#    self.verify_record_task(self.topic + FUNNY_IRI)


end
