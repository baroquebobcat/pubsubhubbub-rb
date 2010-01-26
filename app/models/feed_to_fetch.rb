class FeedToFetch < Ohm::Model
  include Comparable

  """A feed that has new data that needs to be pulled.

  The key name of this entity is a get_hash_key_name() hash of the topic URL, so
  multiple inserts will only ever write a single entity.
  """

  attribute :key_name
  attribute :topic
  attribute :eta
  attribute :fetching_failures
  attribute :totally_failed

  list :source_keys
  list :source_values

  index :key_name

  def self.create(*args)
    # barely handles overwrite...
    feed = get_by_key_name(get_hash_key_name(args.first[:topic]))
    feed.delete if feed

    model = super
    model.eta = Time.now unless model.eta
    model.fetching_failures = 0 unless model.fetching_failures
    model.totally_failed = false unless model.totally_failed
    model.save
    model
  end

  def validate
    assert_unique :key_name
    assert_present(:topic)
  end

  def self.get_by_topic(topic)
    """Retrives a FeedToFetch by the topic URL.

    Args:
      topic: The URL for the feed.

    Returns:
      The FeedToFetch or None if it does not exist.
    """
    get_by_key_name(get_hash_key_name(topic))
  end

  def self.insert(topic_list, source_dict = nil)
    """Inserts a set of FeedToFetch entities for a set of topics.

    Overwrites any existing entities that are already there.

    Args:
      topic_list: List of the topic URLs of feeds that need to be fetched.
      source_dict: Dictionary of sources for the feed. Defaults to an empty
        dictionary.
    """
    return unless topic_list

    if source_dict
      #source_keys, source_values = zip(*source_dict.items())  # Yay Python!
      source_keys, source_values = [], []
    else
      source_keys, source_values = [], []
    end

    feed_list = []
    topic_list.each do |topic|
      feed = FeedToFetch.create(:key_name=>get_hash_key_name(topic), :topic=>topic)
      source_keys.each do |key|
        feed.source_key.add key
      end
      source_values.each do |value|
        feed.source_value.add value
      end
      feed.save
      feed_list.push feed
    end

    feed_list.flatten!

    # TODO(bslatkin): Use a bulk interface or somehow merge combined fetches
    # into a single task.
    feed_list.each do |feed|
      feed.enqueue_task() #unless feed.nil?
    end

  end

  # Maximum number of times to attempt to pull a feed.
  MAX_FEED_PULL_FAILURES = 4

  # Period to use for exponential backoff on feed pulling.
  FEED_PULL_RETRY_PERIOD = 30 # seconds

  def fetch_failed(options = {})

    options = ( { :max_failures=>MAX_FEED_PULL_FAILURES, :retry_period=>FEED_PULL_RETRY_PERIOD, :now=>Time.now } ).merge(options)

    """Reports that feed fetching failed.

    This will mark this feed as failing to fetch. This feed will not be
    refetched until insert() is called again.

    Args:
      max_failures: Maximum failures to allow before giving up.
      retry_period: Initial period for doing exponential (base-2) backoff.
      now: Returns the current time as a UTC datetime.
    """

    if fetching_failures.to_i >= options[:max_failures]
      logger.warn('Max fetching failures exceeded, giving up.')
      write_local(:totally_failed, true)
      save
    else
      retry_delay = options[:retry_period].to_i * (2 ** fetching_failures.to_i)
      logger.warn("Fetching failed. Will retry in #{retry_delay} seconds")
      write_local(:eta, options[:now] + retry_delay)
      write_local(:fetching_failures, fetching_failures.to_i + 1)
      save
      # TODO(bslatkin): Do this enqueuing transactionally.
      enqueue_task()
    end

  end

  def done()
    """The feed fetch has completed successfully.

    This will delete this FeedToFetch entity iff the ETA has not changed,
    meaning a subsequent publish event did not happen for this topic URL. If
    the ETA has changed, then we can safely assume there is a pending Task to
    take care of this FeedToFetch and we should leave the entry.

    Returns:
      True if the entity was deleted, False otherwise.
    """
    other = FeedToFetch.get_by_key_name(key_name)

    if other and other.eta == eta and other.id == id
      other.delete
      return true
    else
      return false
    end
  end

  RETRIES = 3
  FEED_QUEUE = 'feed-pulls'
  FEED_RETRIES_QUEUE = 'feed-pulls-retries'
  POLLING_QUEUE = 'polling'

  def enqueue_task()
    """Enqueues a task to fetch this feed."""
    # TODO(bslatkin): Remove these retries when they're not needed in userland.

    if fetching_failures and fetching_failures.to_i > 0:
      target_queue = FEED_RETRIES_QUEUE
    elsif ENV['HTTP_X_APPENGINE_QUEUENAME'] == POLLING_QUEUE
      target_queue = POLLING_QUEUE
    else
      target_queue = FEED_QUEUE
    end

    (0..RETRIES).each do |i|
      begin
        task = Task.create(:url => '/work/pull_feeds', :eta => Time.now, :params => {'topic'=> topic})
        TaskQueue.add(target_queue, task)
        return
      rescue Error => e
        logger.error("Could not insert task to fetch topic = #{topic}")
        if i == (RETRIES - 1)
          raise
        end
      end
    end

  end

end