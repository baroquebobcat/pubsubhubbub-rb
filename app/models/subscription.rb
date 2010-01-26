class Subscription < Ohm::Model
  include Comparable

  """Represents a single subscription to a topic for a callback URL."""

  DEFAULT_LEASE_SECONDS = (30 * 24 * 60 * 60) # 30 days

  STATE_NOT_VERIFIED = 'not_verified'
  STATE_VERIFIED = 'verified'
  STATE_TO_DELETE = 'to_delete'
  STATES = [
          STATE_NOT_VERIFIED,
          STATE_VERIFIED,
          STATE_TO_DELETE,
  ]

  attribute :key_name
  attribute :callback
  attribute :callback_hash
  attribute :topic
  attribute :topic_hash
  attribute :created_time
  attribute :last_modified
  attribute :lease_seconds
  attribute :expiration_time
  attribute :eta
  attribute :confirm_failures
  attribute :verify_token
  attribute :secret
  attribute :hash_func
  attribute :subscription_state

  index :key_name
  index :topic_hash

  def self.create(*args)
    model = super
    model.created_time = Time.now unless model.created_time
    model.last_modified = Time.now unless model.last_modified
    model.lease_seconds = DEFAULT_LEASE_SECONDS unless model.lease_seconds

    model.eta = Time.now unless model.eta
    model.confirm_failures = 0 unless model.confirm_failures
    model.subscription_state = STATE_NOT_VERIFIED unless model.subscription_state
    model.save
    model
  end

  def validate
    assert_unique :key_name
    assert_present :callback
    assert_present :callback_hash
    assert_present :topic
    assert_present :topic_hash
    assert_present :expiration_time
  end

  def self.create_key_name(callback, topic)
    """Returns the key name for a Subscription entity.

    Args:
      callback: URL of the callback subscriber.
      topic: URL of the topic being subscribed to.

    Returns:
      String containing the key name for the corresponding Subscription.
    """
    return get_hash_key_name("#{callback}\n#{topic}")
  end

  def self.insert(callback, topic, verify_token, secret, options = {})

    options = ({ :hash_func => 'sha1', :lease_seconds => DEFAULT_LEASE_SECONDS, :now => Time.now }).merge(options)

    """Marks a callback URL as being subscribed to a topic.

    Creates a new subscription if None already exists. Forces any existing,
    pending request (i.e., async) to immediately enter the verified state.

    Args:
      callback: URL that will receive callbacks.
      topic: The topic to subscribe to.
      verify_token: The verification token to use to confirm the
        subscription request.
      secret: Shared secret used for HMACs.
      hash_func: String with the name of the hash function to use for HMACs.
      lease_seconds: Number of seconds the client would like the subscription
        to last before expiring. Must be a number.
      now: Callable that returns the current time as a datetime instance. Used
        for testing

    Returns:
      True if the subscription was newly created, False otherwise.
    """
    key_name = create_key_name(callback, topic)

    sub_is_new = false
    sub = get_by_key_name(key_name)
    unless sub
      sub_is_new = true
      sub = Subscription.create(:key_name => key_name,
                                :callback => callback,
                                :callback_hash => sha1_hash(callback),
                                :topic => topic,
                                :topic_hash => sha1_hash(topic),
                                :verify_token => verify_token,
                                :secret => secret,
                                :hash_func => options[:hash_func],
                                :lease_seconds => options[:lease_seconds],
                                :expiration_time => options[:now])
    end
    sub.subscription_state = STATE_VERIFIED
    sub.expiration_time = options[:now] + options[:lease_seconds]
    sub.confirm_failures = 0
    sub.verify_token = verify_token
    sub.secret = secret
    sub.save
    sub_is_new
  end

  def self.request_insert(callback, topic, verify_token, secret, options = {})

    options = ({ :auto_reconfirm => false, :hash_func => 'sha1', :lease_seconds => DEFAULT_LEASE_SECONDS, :now => Time.now }).merge(options)

    """Records that a callback URL needs verification before being subscribed.

    Creates a new subscription request (for asynchronous verification) if None
    already exists. Any existing subscription request will not be modified;
    for instance, if a subscription has already been verified, this method
    will do nothing.

    Args:
      callback: URL that will receive callbacks.
      topic: The topic to subscribe to.
      verify_token: The verification token to use to confirm the
        subscription request.
      secret: Shared secret used for HMACs.
      auto_reconfirm: True if this task is being run by the auto-reconfirmation
        offline process; False if this is a user-requested task. Defaults
        to False.
      hash_func: String with the name of the hash function to use for HMACs.
      lease_seconds: Number of seconds the client would like the subscription
        to last before expiring. Must be a number.
      now: Callable that returns the current time as a datetime instance. Used
        for testing

    Returns:
      True if the subscription request was newly created, False otherwise.
    """
    key_name = create_key_name(callback, topic)
    sub_is_new = false
    sub = get_by_key_name(key_name)
    unless sub
      sub_is_new = true
      sub = Subscription.create(:key_name => key_name,
                                :callback => callback,
                                :callback_hash => sha1_hash(callback),
                                :topic => topic,
                                :topic_hash => sha1_hash(topic),
                                :verify_token => verify_token,
                                :secret => secret,
                                :hash_func=>options[:hash_func],
                                :lease_seconds => options[:lease_seconds],
                                :expiration_time => options[:now] + options[:lease_seconds])
    end
    sub.confirm_failures = 0
    sub.save

    # Note: This enqueuing must come *after* the transaction is submitted, or
    # else we'll actually run the task *before* the transaction is submitted.
    sub.enqueue_task(STATE_VERIFIED, verify_token, :secret => secret, :auto_reconfirm => options[:auto_reconfirm])
    sub_is_new
  end

  def self.remove(callback, topic)
    """Causes a callback URL to no longer be subscribed to a topic.

    If the callback was not already subscribed to the topic, this method
    will do nothing. Otherwise, the subscription will immediately be removed.

    Args:
      callback: URL that will receive callbacks.
      topic: The topic to subscribe to.

    Returns:
      True if the subscription had previously existed, False otherwise.
    """
    key_name = create_key_name(callback, topic)
    sub = get_by_key_name(key_name)
    if sub
      sub.delete()
      return true
    end
    false
  end

  def self.request_remove(callback, topic, verify_token)
    """Records that a callback URL needs to be unsubscribed.

    Creates a new request to unsubscribe a callback URL from a topic (where
    verification should happen asynchronously). If an unsubscribe request
    has already been made, this method will do nothing.

    Args:
      callback: URL that will receive callbacks.
      topic: The topic to subscribe to.
      verify_token: The verification token to use to confirm the
        unsubscription request.

    Returns:
      True if the Subscription to remove actually exists, False otherwise.
    """
    key_name = create_key_name(callback, topic)
    sub = get_by_key_name(key_name)
    removed = false
    if sub
      sub.confirm_failures = 0
      sub.save
      removed = true
    end

    # Note: This enqueuing must come *after* the transaction is submitted, or
    # else we'll actually run the task *before* the transaction is submitted.
    if sub
      sub.enqueue_task(STATE_TO_DELETE, verify_token)
    end
    removed
  end

  def self.archive(callback, topic)
    """Archives a subscription as no longer active.

    Args:
      callback: URL that will receive callbacks.
      topic: The topic to subscribe to.
    """
    key_name = create_key_name(callback, topic)
    sub = get_by_key_name(key_name)
    if sub
      sub.subscription_state = STATE_TO_DELETE
      sub.confirm_failures = 0
      sub.save
    end
  end

  def self.has_subscribers(topic)
    """Check if a topic URL has verified subscribers.

    Args:
      topic: The topic URL to check for subscribers.

    Returns:
      True if it has verified subscribers, False otherwise.
    """
    #(Subscriber.all().filter('topic_hash =', sha1_hash(topic)).filter('subscription_state =', cls.STATE_VERIFIED).get())

    subscribers(topic, 1).size > 0
  end

  def self.subscribers(topic, count)
    subscribers = []
    find(:topic_hash=>sha1_hash(topic)).all.each do |subscriber|
      subscribers << subscriber if subscriber.subscription_state.eql? STATE_VERIFIED
      break if count == subscribers.size
    end
    subscribers
  end

  def self.get_subscribers(topic, count, starting_at_callback=nil)
    """Gets the list of subscribers starting at an offset.

    Args:
      topic: The topic URL to retrieve subscribers for.
      count: How many subscribers to retrieve.
      starting_at_callback: A string containing the callback hash to offset
        to when retrieving more subscribers. The callback at the given offset
        *will* be included in the results. If None, then subscribers will
        be retrieved from the beginning.

    Returns:
      List of Subscription objects that were found, or an empty list if none
      were found.
    """
#    query = all()
#    query.filter('topic_hash =', sha1_hash(topic))
#    query.filter('subscription_state = ', cls.STATE_VERIFIED)
#    if starting_at_callback:
#      query.filter('callback_hash >=', sha1_hash(starting_at_callback))
#    query.order('callback_hash')
#
#    return query.fetch(count)

    # todo - (barinek) implement filter...

    subscribers(topic, count)
  end

  RETRIES = 3
  SUBSCRIPTION_QUEUE = 'subscriptions'
  POLLING_QUEUE = 'polling'

  def enqueue_task(next_state, verify_token, options = {})

    options = {:auto_reconfirm => false, :secret => nil}.merge(options)

    """Enqueues a task to confirm this Subscription.

    Args:
      next_state: The next state this subscription should be in.
      verify_token: The verify_token to use when confirming this request.
      auto_reconfirm: True if this task is being run by the auto-reconfirmation
        offline process; False if this is a user-requested task. Defaults
        to False.
      secret: Only required for subscription confirmation (not unsubscribe).
        The new secret to use for this subscription after successful
        confirmation.
    """
    # TODO(bslatkin): Remove these retries when they're not needed in userland.

    if ENV['HTTP_X_APPENGINE_QUEUENAME'] == POLLING_QUEUE
      target_queue = POLLING_QUEUE
    else
      target_queue = SUBSCRIPTION_QUEUE
    end

    (0..RETRIES).each do |i|
      begin
        task = Task.create(:url => '/work/subscriptions', :eta => eta, :params => {
                'subscription_key_name' => key_name,
                'next_state' => next_state,
                'verify_token' => verify_token,
                'secret' => options[:secret] ? options[:secret] : '',
                'auto_reconfirm' => options[:auto_reconfirm]
        })
        TaskQueue.add(target_queue, task)
        return
      rescue Error => e
        logger.error("Could not insert task to confirm 'topic = #{topic}, callback = #{callback}")
        if i == (RETRIES - 1)
          raise
        end
      end
    end

  end


  MAX_SUBSCRIPTION_CONFIRM_FAILURES = 4
  SUBSCRIPTION_RETRY_PERIOD = 30 # seconds

  def confirm_failed(next_state, verify_token, auto_reconfirm = false, options = {})

    options = {:secret => nil, :max_failures => MAX_SUBSCRIPTION_CONFIRM_FAILURES, :retry_period => SUBSCRIPTION_RETRY_PERIOD, :now => Time.now}.merge(options)

    """Reports that an asynchronous confirmation request has failed.

    This will delete this entity if the maximum number of failures has been
    exceeded.

    Args:
      next_state: The next state this subscription should be in.
      verify_token: The verify_token to use when confirming this request.
      auto_reconfirm: True if this task is being run by the auto-reconfirmation
        offline process; False if this is a user-requested task.
      secret: The new secret to use for this subscription after successful
        confirmation.
      max_failures: Maximum failures to allow before giving up.
      retry_period: Initial period for doing exponential (base-2) backoff.
      now: Returns the current time as a UTC datetime.

    Returns:
      True if this Subscription confirmation should be retried again. Returns
      False if we should give up and never try again.
    """
    if confirm_failures.to_i >= options[:max_failures]
      logger.warn('Max subscription failures exceeded, giving up.')
      return false
    else
      retry_delay = options[:retry_period] * (2 ** confirm_failures.to_i)
      write_local(:eta, options[:now] + retry_delay)
      write_local(:confirm_failures, (confirm_failures.to_i + 1))
      save

      # TODO(bslatkin): Do this enqueuing transactionally.
      enqueue_task(next_state, verify_token, :auto_reconfirm => auto_reconfirm, :secret => options[:secret])
      return true
    end

  end

end