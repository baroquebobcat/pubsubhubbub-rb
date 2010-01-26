require File.dirname(__FILE__) + '/../test_helper'

class SubscriptionTest < Test::Unit::TestCase
  """Tests for the Subscription model class."""

  setup do
    Ohm.flush

    """Sets up the test harness."""
    @callback = 'http://example.com/my-callback-url'
    @callback2 = 'http://example.com/second-callback-url'
    @callback3 = 'http://example.com/third-callback-url'
    @topic = 'http://example.com/my-topic-url'
    @topic2 = 'http://example.com/second-topic-url'
    @token = 'token'
    @secret = 'my secrat'
    @callback_key_map = [@callback, @callback2, @callback3].collect do |callback|
      Subscription.create_key_name(callback, @topic)
    end

  end

  def get_subscription
    """Returns the subscription for the test callback and topic."""
    return Subscription.get_by_key_name(Subscription.create_key_name(@callback, @topic))
  end

  def verify_tasks(next_state, verify_token, secret, options = {})
    """Verifies the required tasks have been submitted.

    Args:
      next_state: The next state the Subscription should have.
      verify_token: The token that should be used to confirm the
        subscription action.
      **kwargs: Passed to testutil.get_tasks().
    """

    tasks = TaskQueue.all(Subscription::SUBSCRIPTION_QUEUE)

    assert_equal options[:expected_count], tasks.size
    task = tasks[options[:index]]

    assertEquals(next_state, task.params['next_state'])
    assertEquals(verify_token, task.params['verify_token'])
    assertEquals(secret, task.params['secret'])
  end

  should "testRequestInsert_defaults" do
    now = Time.now
    lease_seconds = 1234

    assertTrue(Subscription.request_insert(
            @callback, @topic, @token,
            @secret, :lease_seconds=>lease_seconds, :now=>now))

    verify_tasks(Subscription::STATE_VERIFIED, @token, @secret, :expected_count=>1, :index=>0)

    assertFalse(Subscription.request_insert(
            @callback, @topic, @token,
            @secret, :lease_seconds=>lease_seconds, :now=>now))

    verify_tasks(Subscription::STATE_VERIFIED, @token, @secret, :expected_count=>2, :index=>1)

    sub = get_subscription()
    assertEquals(Subscription::STATE_NOT_VERIFIED, sub.subscription_state)
    assertEquals(@callback, sub.callback)
    assertEquals(Subscription.sha1_hash(@callback), sub.callback_hash)
    assertEquals(@topic, sub.topic)
    assertEquals(Subscription.sha1_hash(@topic), sub.topic_hash)
    assertEquals(@token, sub.verify_token)
    assertEquals(@secret, sub.secret)
    assertEquals(0, sub.confirm_failures.to_i)
    assert(now + lease_seconds).to_i == Time.parse(sub.expiration_time).to_i
    assertEquals(lease_seconds, sub.lease_seconds.to_i)
  end

  should "testInsert_defaults" do
    now = Time.now
    lease_seconds = 1234

    assertTrue(Subscription.insert(
            @callback, @topic, @token, @secret,
            :lease_seconds=>lease_seconds, :now=>now))
    assertFalse(Subscription.insert(
            @callback, @topic, @token, @secret,
            :lease_seconds=>lease_seconds, :now=>now))

    tasks = TaskQueue.all(Subscription::SUBSCRIPTION_QUEUE)
    assert_equal 0, tasks.size

    sub = get_subscription()
    assertEquals(Subscription::STATE_VERIFIED, sub.subscription_state)
    assertEquals(@callback, sub.callback)
    assertEquals(Subscription.sha1_hash(@callback), sub.callback_hash)
    assertEquals(@topic, sub.topic)
    assertEquals(Subscription.sha1_hash(@topic), sub.topic_hash)
    assertEquals(@token, sub.verify_token)
    assertEquals(@secret, sub.secret)
    assertEquals(0, sub.confirm_failures.to_i)
    assert (now+lease_seconds).to_i == Time.parse(sub.expiration_time).to_i
    assertEquals(lease_seconds, sub.lease_seconds.to_i)

  end

  should "testInsertOverride" do
    """Tests that insert will override the existing Subscription fields."""
    assertTrue(Subscription.request_insert(
            @callback, @topic, @token, @secret))
    assertEquals(Subscription::STATE_NOT_VERIFIED,
                 get_subscription().subscription_state)

    second_token = 'second token'
    second_secret = 'second secret'
    sub = get_subscription()
    sub.confirm_failures = 123
    sub.save
    assertFalse(Subscription.insert(
            @callback, @topic, second_token, second_secret))

    sub = self.get_subscription()
    assertEquals(Subscription::STATE_VERIFIED, sub.subscription_state)
    assertEquals(0, sub.confirm_failures.to_i)
    assertEquals(second_token, sub.verify_token)
    assertEquals(second_secret, sub.secret)

    verify_tasks(Subscription::STATE_VERIFIED, @token, @secret, :expected_count=>1, :index=>0)

  end

  should "testInsert_expiration" do
    """Tests that the expiration time is updated on repeated insert() calls."""
    assertTrue(Subscription.insert(
            @callback, @topic, @token, @secret))
    sub = Subscription.all().first
    expiration1 = sub.expiration_time
    sleep(0.5)
    assertFalse(Subscription.insert(
            @callback, @topic, @token, @secret, :now => Time.now+1))
    sub = Subscription.find(:key_name => sub.key_name()).first
    expiration2 = sub.expiration_time
    assertTrue(expiration2 > expiration1)
  end

  should "testRemove" do
    assertFalse(Subscription.remove(@callback, @topic))
    assertTrue(Subscription.request_insert(
            @callback, @topic, @token, @secret))
    assertTrue(Subscription.remove(@callback, @topic))
    assertFalse(Subscription.remove(@callback, @topic))
    # Only task should be the initial insertion request.
    verify_tasks(Subscription::STATE_VERIFIED, @token, @secret,
                 :expected_count=>1, :index=>0)
  end

  should "testRequestRemove" do
    """Tests the request remove method."""
    assertFalse(Subscription.request_remove(
            @callback, @topic, @token))
    # No tasks should be enqueued and this request should do nothing because
    # no subscription currently exists.
    tasks = TaskQueue.all(Subscription::SUBSCRIPTION_QUEUE)
    assert_equal 0, tasks.size

    assertTrue(Subscription.request_insert(
            @callback, @topic, @token, @secret))
    second_token = 'this is the second token'
    assertTrue(Subscription.request_remove(
            @callback, @topic, second_token))

    sub = get_subscription()
    assertEquals(@token, sub.verify_token)
    assertEquals(Subscription::STATE_NOT_VERIFIED, sub.subscription_state)

    verify_tasks(Subscription::STATE_VERIFIED, @token, @secret,
                 :expected_count=>2, :index=>0)

    verify_tasks(Subscription::STATE_TO_DELETE, second_token, '',
                 :expected_count=>2, :index=>1)
  end

  should "testRequestInsertOverride" do
    """Tests that requesting insertion does not override the verify_token."""
    assertTrue(Subscription.insert(
            @callback, @topic, @token, @secret))
    second_token = 'this is the second token'
    second_secret = 'another secret here'
    assertFalse(Subscription.request_insert(
            @callback, @topic, second_token, second_secret))

    sub = get_subscription()
    assertEquals(@token, sub.verify_token)
    assertEquals(Subscription::STATE_VERIFIED, sub.subscription_state)

    verify_tasks(Subscription::STATE_VERIFIED, second_token, second_secret,
                 :expected_count=>1, :index=>0)
  end

  should "testHasSubscribers_unverified" do
    """Tests that unverified subscribers do not make the subscription active."""
    assertFalse(Subscription.has_subscribers(@topic))
    assertTrue(Subscription.request_insert(
            @callback, @topic, @token, @secret))
    assertFalse(Subscription.has_subscribers(@topic))
  end

  should "testHasSubscribers_verified" do
    assertTrue(Subscription.insert(
            @callback, @topic, @token, @secret))
    assertTrue(Subscription.has_subscribers(@topic))
    assertTrue(Subscription.remove(@callback, @topic))
    assertFalse(Subscription.has_subscribers(@topic))
  end

  should "testGetSubscribers_unverified" do
    """Tests that unverified subscribers will not be retrieved."""
    assertEquals([], Subscription.get_subscribers(@topic, 10))
    assertTrue(Subscription.request_insert(
            @callback, @topic, @token, @secret))
    assertTrue(Subscription.request_insert(
            @callback2, @topic, @token, @secret))
    assertTrue(Subscription.request_insert(
            @callback3, @topic, @token, @secret))
    assertEquals([], Subscription.get_subscribers(@topic, 10))
  end

  should "testGetSubscribers_verified" do
    assertEquals([], Subscription.get_subscribers(@topic, 10))
    assertTrue(Subscription.insert(
            @callback, @topic, @token, @secret))
    assertTrue(Subscription.insert(
            @callback2, @topic, @token, @secret))
    assertTrue(Subscription.insert(
            @callback3, @topic, @token, @secret))
    sub_list = Subscription.get_subscribers(@topic, 10)

    found_keys = sub_list.collect do |subscription|
      subscription.key_name
    end
    assertEquals(@callback_key_map.sort, found_keys.sort)
  end

  should "testGetSubscribers_count" do
    assertTrue(Subscription.insert(
            @callback, @topic, @token, @secret))
    assertTrue(Subscription.insert(
            @callback2, @topic, @token, @secret))
    assertTrue(Subscription.insert(
            @callback3, @topic, @token, @secret))
    sub_list = Subscription.get_subscribers(@topic, 1)
    assertEquals(1, sub_list.size)
  end

# todo...
  
#  def testGetSubscribers_withOffset(self):
#    """Tests the behavior of the starting_at_callback offset parameter."""
#    # In the order the query will sort them.
#    all_hashes = [
#        u'87a74994e48399251782eb401e9a61bd1d55aeee',
#        u'01518f29da9db10888a92e9f0211ac0c98ec7ecb',
#        u'f745d00a9806a5cdd39f16cd9eff80e8f064cfee',
#    ]
#    all_keys = ['hash_' + h for h in all_hashes]
#    all_callbacks = [self.callback_key_map[k] for k in all_keys]
#
#    self.assertTrue(Subscription.insert(
#        self.callback, self.topic, self.token, self.secret))
#    self.assertTrue(Subscription.insert(
#        self.callback2, self.topic, self.token, self.secret))
#    self.assertTrue(Subscription.insert(
#        self.callback3, self.topic, self.token, self.secret))
#
#    def key_list(starting_at_callback):
#      sub_list = Subscription.get_subscribers(
#          self.topic, 10, starting_at_callback=starting_at_callback)
#      return [s.key().name() for s in sub_list]
#
#    self.assertEquals(all_keys, key_list(None))
#    self.assertEquals(all_keys, key_list(all_callbacks[0]))
#    self.assertEquals(all_keys[1:], key_list(all_callbacks[1]))
#    self.assertEquals(all_keys[2:], key_list(all_callbacks[2]))

  should "testGetSubscribers_multipleTopics" do
    """Tests that separate topics do not overlap in subscriber queries."""
    assertEquals([], Subscription.get_subscribers(@topic2, 10))
    assertTrue(Subscription.insert(
            @callback, @topic, @token, @secret))
    assertTrue(Subscription.insert(
            @callback2, @topic, @token, @secret))
    assertTrue(Subscription.insert(
            @callback3, @topic, @token, @secret))
    assertEquals([], Subscription.get_subscribers(@topic2, 10))

    assertTrue(Subscription.insert(
            @callback2, @topic2, @token, @secret))
    assertTrue(Subscription.insert(
            @callback3, @topic2, @token, @secret))
    sub_list = Subscription.get_subscribers(@topic2, 10)

    found_keys = sub_list.collect do |subscription|
      subscription.key_name
    end
    assertEquals(
            [@callback2, @callback3].collect { |callback|
              Subscription.create_key_name(callback, @topic2) }.sort,
            found_keys.sort)
    assertEquals(3, Subscription.get_subscribers(@topic, 10).size)
  end

  should "testConfirmFailed" do
    """Tests retry delay periods when a subscription confirmation fails."""
    start = Time.now

    sub_key = Subscription.create_key_name(@callback, @topic)
    assertTrue(Subscription.request_insert(
            @callback, @topic, @token, @secret))
    sub_key = Subscription.create_key_name(@callback, @topic)
    sub = Subscription.get_by_key_name(sub_key)
    assertEquals(0, sub.confirm_failures.to_i)

    [5, 10, 20, 40, 80].each_with_index do | delay, i |
      assertTrue(
              sub.confirm_failed(Subscription::STATE_VERIFIED, @token, false, :max_failures=>5, :retry_period=>5, :now=>start))

      assertEquals(sub.eta, start + delay)
      assertEquals(i+1, sub.confirm_failures)
    end

    # It will give up on the last try.
    assertFalse(
            sub.confirm_failed(Subscription::STATE_VERIFIED, @token, false,
                               :max_failures=>5, :retry_period=>5))
    sub = Subscription.get_by_key_name(sub_key)
    assertEquals(Subscription::STATE_NOT_VERIFIED, sub.subscription_state)

    tasks = TaskQueue.all(Subscription::SUBSCRIPTION_QUEUE)
    assert_equal 6, tasks.size
  end


  should "testQueuePreserved" do
    """Tests that insert will put the task on the polling queue."""
    assertTrue(Subscription.request_insert(
            @callback, @topic, @token, @secret))

    tasks = TaskQueue.all(Subscription::SUBSCRIPTION_QUEUE)
    assert_equal 1, tasks.size

    ENV['HTTP_X_APPENGINE_QUEUENAME'] = Subscription::POLLING_QUEUE

    assertFalse(Subscription.request_insert(
            @callback, @topic, @token, @secret))

    ENV['HTTP_X_APPENGINE_QUEUENAME'] = nil

    tasks = TaskQueue.all(Subscription::SUBSCRIPTION_QUEUE)
    assert_equal 1, tasks.size

    tasks = TaskQueue.all(Subscription::POLLING_QUEUE)
    assert_equal 1, tasks.size

  end

  should "testArchiveExists" do
    """Tests the archive method when the subscription exists."""
    Subscription.insert(@callback, @topic, @token, @secret)
    sub_key = Subscription.create_key_name(@callback, @topic)
    sub = Subscription.get_by_key_name(sub_key)
    assertEquals(Subscription::STATE_VERIFIED, sub.subscription_state)
    Subscription.archive(@callback, @topic)
    sub = Subscription.get_by_key_name(sub_key)
    assertEquals(Subscription::STATE_TO_DELETE, sub.subscription_state)
  end

  should "testArchiveMissing" do
    """Tests the archive method when the subscription does not exist."""
    sub_key = Subscription.create_key_name(@callback, @topic)
    assertTrue(Subscription.get_by_key_name(sub_key).nil?)
    Subscription.archive(@callback, @topic)
    assertTrue(Subscription.get_by_key_name(sub_key).nil?)
  end

end