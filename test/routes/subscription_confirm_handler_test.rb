require File.dirname(__FILE__) + '/../stories_helper'
require "stories_helper"

class SubscribeConfirmHandlerTest < Test::Unit::TestCase
  include Mocha::API

  def handle(method, options = {})
    post "/work/subscriptions", options
  end

  setup do
    Ohm.flush

    """Sets up the test fixture."""

    @callback = 'http://example.com/good-callback'
    @topic = 'http://example.com/the-topic'
    @sub_key = Subscription.create_key_name(@callback, @topic)
    @verify_token = 'the_token'
    @secret = 'teh secrat'

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '200', :body => 'this_is_my_fake_challenge_string')
    Net::HTTP.any_instance.expects(:request).at_least_once.returns(@http_mock)

  end

  def verify_task(next_state, options = {})
    """Verifies that a subscription worker task is present.

    Args:
      next_state: The next state the task should cause the Subscription to have.
    """
    options = ({:index=>0, :expected_count=>1 }).merge(options)

    tasks = TaskQueue.all(Subscription::SUBSCRIPTION_QUEUE)
    assert_equal options[:expected_count], tasks.size
    task = tasks[options[:index]]

    self.assertEquals(@sub_key, task.params['subscription_key_name'])
    self.assertEquals(next_state, task.params['next_state'])
  end


  def verify_retry_task(eta, next_state, options = {})
    """Verifies that a subscription worker retry task is present.

    Args:
      eta: The ETA the retry task should have.
      next_state: The next state the task should cause the Subscription to have.
      verify_token: The verify token the retry task should have. Defaults to
        the current token.
      secret: The secret the retry task should have. Defaults to the
        current secret.
      auto_reconfirm: The confirmation type the retry task should have.
    """


    options = ({:verify_token=>nil,
                :secret=>nil,
                :auto_reconfirm=>false, :index=>1, :expected_count=>2

    }).merge(options)

    tasks = TaskQueue.all(Subscription::SUBSCRIPTION_QUEUE)
    assert_equal options[:expected_count], tasks.size
    task = tasks[options[:index]]

    self.assertEquals(@sub_key, task.params['subscription_key_name'])
    self.assertEquals(next_state, task.params['next_state'])
    self.assertEquals(options[:verify_token] ||= @verify_token, task.params['verify_token'])
    self.assertEquals(options[:secret] ||= @secret, task.params['secret'])
    self.assertEquals(options[:auto_reconfirm], task.params['auto_reconfirm'])

  end

  def verify_record_task(topic, options = {})
    """Tests there is a valid KnownFeedIdentity task enqueued.

    Args:
      topic: The topic the task should be for.

    Raises:
      AssertionError if the task isn't there.
    """

    options = ({:index=>0, :expected_count=>1 }).merge(options)

    tasks = TaskQueue.all(KnownFeed::MAPPINGS_QUEUE)

    assert_equal options[:expected_count], tasks.size
    task = tasks[options[:index]]

    self.assertEquals(topic, task.params['topic'])

  end

  should "testNoWork" do
    """Tests when a task is enqueued for a Subscription that doesn't exist."""

    self.handle('post', {'subscription_key_name' => 'unknown',
                         'next_state' => Subscription::STATE_VERIFIED})
  end

  should "testSubscribeSuccessful" do
    """Tests when a subscription task is successful."""
    self.assertTrue(KnownFeed.get_by_key_name(KnownFeed.create_key(@topic)).nil?)
    self.assertTrue(Subscription.get_by_key_name(@sub_key).nil?)

    Subscription.request_insert(
            @callback, @topic, @verify_token, @secret)

    self.handle('post', {'subscription_key_name', @sub_key,
                         'verify_token', @verify_token,
                         'secret', @secret,
                         'next_state', Subscription::STATE_VERIFIED})


    self.verify_task(Subscription::STATE_VERIFIED, :index=>0, :expected_count =>1)
    self.verify_record_task(@topic, :index=>0, :expected_count =>1)

    sub = Subscription.get_by_key_name(@sub_key)
    self.assertEquals(Subscription::STATE_VERIFIED, sub.subscription_state)
    self.assertEquals(@verify_token, @verify_token)
    self.assertEquals(@secret, sub.secret)
  end

  should "testSubscribeFailed" do
    """Tests when a subscription task fails."""
    self.assertTrue(Subscription.get_by_key_name(@sub_key).nil?)
    Subscription.request_insert(
            @callback, @topic, @verify_token, @secret)

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '500', :body => '')
    Net::HTTP.any_instance.expects(:request).at_least_once.returns(@http_mock)

    self.handle('post', {'subscription_key_name' => @sub_key,
                         'verify_token' => @verify_token,
                         'secret' => @secret,
                         'next_state' => Subscription::STATE_VERIFIED,
                         'auto_reconfirm' => true})

    sub = Subscription.get_by_key_name(@sub_key)

    self.assertEquals(Subscription::STATE_NOT_VERIFIED, sub.subscription_state)
    self.assertEquals(1, sub.confirm_failures.to_i)
    self.assertEquals(@verify_token, @verify_token)
    self.assertEquals(@secret, sub.secret)

    self.verify_retry_task(sub.eta, Subscription::STATE_VERIFIED,
                           :auto_reconfirm=>true,
                           :verify_token=>@verify_token,
                           :secret=>@secret)
  end

  should "testSubscribeConflict" do
    """Tests when confirmation hits a conflict and archives the subscription."""
    self.assertTrue(Subscription.get_by_key_name(@sub_key).nil?)
    Subscription.request_insert(
            @callback, @topic, @verify_token, @secret)

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '404', :body => '')
    Net::HTTP.any_instance.expects(:request).at_least_once.returns(@http_mock)

    self.handle('post', {'subscription_key_name', @sub_key,
                         'verify_token', @verify_token,
                         'secret', @secret,
                         'next_state', Subscription::STATE_VERIFIED})
    sub = Subscription.get_by_key_name(@sub_key)

    self.assertEquals(Subscription::STATE_TO_DELETE, sub.subscription_state)

    assert_equal 1, TaskQueue.all(Subscription::SUBSCRIPTION_QUEUE).count

  end

  should "testSubscribeBadChallengeResponse" do
    """Tests when the subscriber responds with a bad challenge."""
    self.assertTrue(Subscription.get_by_key_name(@sub_key).nil?)
    Subscription.request_insert(
            @callback, @topic, @verify_token, @secret)

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '200', :body => 'bad')
    Net::HTTP.any_instance.expects(:request).at_least_once.returns(@http_mock)

    self.handle('post', {'subscription_key_name' => @sub_key,
                         'verify_token' => @verify_token,
                         'secret' => @secret,
                         'next_state' => Subscription::STATE_VERIFIED})
    sub = Subscription.get_by_key_name(@sub_key)
    self.assertEquals(Subscription::STATE_NOT_VERIFIED, sub.subscription_state)
    self.assertEquals(1, sub.confirm_failures.to_i)

    # todo - unique task thing again...
#    self.verify_retry_task(sub.eta, Subscription::STATE_VERIFIED)
  end

  should "testUnsubscribeSuccessful" do
    """Tests when an unsubscription request is successful."""
    self.assertTrue(Subscription.get_by_key_name(@sub_key).nil?)
    Subscription.insert(
            @callback, @topic, @verify_token, @secret)
    Subscription.request_remove(@callback, @topic, @verify_token)

    self.handle('post', {'subscription_key_name', @sub_key,
                         'verify_token', @verify_token,
                         'next_state', Subscription::STATE_TO_DELETE})

    self.verify_task(Subscription::STATE_TO_DELETE)
    self.assertTrue(Subscription.get_by_key_name(@sub_key).nil?)
  end

  should "testUnsubscribeFailed" do
    """Tests when an unsubscription task fails."""
    self.assertTrue(Subscription.get_by_key_name(@sub_key).nil?)
    Subscription.insert(
            @callback, @topic, @verify_token, @secret)
    Subscription.request_remove(@callback, @topic, @verify_token)

    @http_mock = mock('Net::HTTPResponse')
    @http_mock.stubs(:code => '500', :body => '')
    Net::HTTP.any_instance.expects(:request).at_least_once.returns(@http_mock)


    self.handle('post', {'subscription_key_name' => @sub_key,
                         'verify_token' => @verify_token,
                         'next_state' => Subscription::STATE_TO_DELETE,
                         'secret' => @secret})
    sub = Subscription.get_by_key_name(@sub_key)
    self.assertEquals(1, sub.confirm_failures.to_i)

    # todo - fix this...
    # self.verify_retry_task(sub.eta, Subscription::STATE_TO_DELETE)
  end

#  def testUnsubscribeGivesUp(self):
#    """Tests when an unsubscription task completely gives up."""
#    self.assertTrue(Subscription.get_by_key_name(self.sub_key) is None)
#    Subscription.insert(
#        self.callback, self.topic, self.verify_token, self.secret)
#    Subscription.request_remove(self.callback, self.topic, self.verify_token)
#    sub = Subscription.get_by_key_name(self.sub_key)
#    sub.confirm_failures = 100
#    sub.put()
#    urlfetch_test_stub.instance.expect('get',
#        self.verify_callback_querystring_template % 'unsubscribe', 500, '')
#    self.handle('post', ('subscription_key_name', self.sub_key),
#                        ('verify_token', self.verify_token),
#                        ('next_state', Subscription.STATE_TO_DELETE))
#    sub = Subscription.get_by_key_name(self.sub_key)
#    self.assertEquals(100, sub.confirm_failures)
#    self.assertEquals(Subscription.STATE_VERIFIED, sub.subscription_state)
#    self.verify_task(Subscription.STATE_TO_DELETE)
#
  should "testSubscribeOverwrite" do
    """Tests that subscriptions can be overwritten with new parameters."""
    Subscription.insert(
            @callback, @topic, @verify_token, @secret)
    second_token = 'second_verify_token'
    second_secret = 'second secret'

    self.handle('post', {'subscription_key_name' => @sub_key,
                         'verify_token' => second_token,
                         'secret' => second_secret,
                         'next_state' => Subscription::STATE_VERIFIED})
    sub = Subscription.get_by_key_name(@sub_key)
    self.assertEquals(Subscription::STATE_VERIFIED, sub.subscription_state)
    self.assertEquals(second_token, sub.verify_token)
    self.assertEquals(second_secret, sub.secret)
    self.verify_record_task(@topic)
  end

#
#  def testConfirmError(self):
#    """Tests when an exception is raised while confirming a subscription.
#
#    This will just propagate up in the stack and cause the task to retry
#    via the normal task queue retries.
#    """
#    called = [False]
#    Subscription.request_insert(
#        self.callback, self.topic, self.verify_token, self.secret)
#    # All exceptions should just fall through.
#    def new_confirm(*args):
#      called[0] = True
#      raise db.Error()
#    try:
#      main.hooks.override_for_test(main.confirm_subscription, new_confirm)
#      try:
#        self.handle('post', ('subscription_key_name', self.sub_key))
#      except db.Error:
#        pass
#      else:
#        self.fail()
#    finally:
#      main.hooks.reset_for_test(main.confirm_subscription)
#    self.assertTrue(called[0])
#    self.verify_task(Subscription.STATE_VERIFIED)
#
#  def testRenewNack(self):
#    """Tests when an auto-subscription-renewal returns a 404."""
#    self.assertTrue(Subscription.get_by_key_name(self.sub_key) is None)
#    Subscription.insert(
#        self.callback, self.topic, self.verify_token, self.secret)
#    urlfetch_test_stub.instance.expect('get',
#        self.verify_callback_querystring_template % 'subscribe', 404, '')
#    self.handle('post', ('subscription_key_name', self.sub_key),
#                        ('verify_token', self.verify_token),
#                        ('secret', self.secret),
#                        ('next_state', Subscription.STATE_VERIFIED),
#                        ('auto_reconfirm', 'True'))
#    sub = Subscription.get_by_key_name(self.sub_key)
#    self.assertEquals(Subscription.STATE_TO_DELETE, sub.subscription_state)
#    testutil.get_tasks(main.SUBSCRIPTION_QUEUE, expected_count=0)
#
#  def testRenewErrorFailure(self):
#    """Tests when an auto-subscription-renewal returns errors repeatedly.
#
#    In this case, since it's auto-renewal, the subscription should be dropped.
#    """
#    self.assertTrue(Subscription.get_by_key_name(self.sub_key) is None)
#    Subscription.insert(
#        self.callback, self.topic, self.verify_token, self.secret)
#    sub = Subscription.get_by_key_name(self.sub_key)
#    sub.confirm_failures = 100
#    sub.put()
#    urlfetch_test_stub.instance.expect('get',
#        self.verify_callback_querystring_template % 'subscribe', 500, '')
#    self.handle('post', ('subscription_key_name', self.sub_key),
#                        ('verify_token', self.verify_token),
#                        ('next_state', Subscription.STATE_VERIFIED),
#                        ('auto_reconfirm', 'True'))
#    sub = Subscription.get_by_key_name(self.sub_key)
#    self.assertEquals(Subscription.STATE_TO_DELETE, sub.subscription_state)
#    testutil.get_tasks(main.SUBSCRIPTION_QUEUE, expected_count=0)

end