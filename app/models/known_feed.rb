class KnownFeed < Ohm::Model
  include Comparable

  """Represents a feed that we know exists.

  This entity will be overwritten anytime someone subscribes to this feed. The
  benefit is we have a single entity per known feed, allowing us to quickly
  iterate through all of them. This may have issues if the subscription rate
  for a single feed is over one per second.
  """

  attribute :key_name
  attribute :topic
  attribute :feed_id
  attribute :update_time

  index :key_name

  def self.create(*args)
    model = super
    model.key_name = KnownFeed.create_key(model.topic) unless model.key_name
    model.update_time = Time.now.to_f unless model.update_time
    model.save
    model
  end

  def validate
    assert_unique(:key_name)
    assert_present(:topic)
  end

  def self.create_from(topic)
    create_with_key_name(:topic => topic)
  end

  def self.create_with_key_name(hash = {})
    """Creates a new KnownFeed.

     Args:
       topic: The feed's topic URL.

     Returns:
       The KnownFeed instance that hasn't been added to the Datastore.
     """
    key_name = create_key(hash[:topic])
    create( { :key_name => key_name, :topic => hash[:topic] } )
  end

  RETRIES = 3
  MAPPINGS_QUEUE = 'mappings'

  def self.record(topic)
    """Enqueues a task to create a new KnownFeed and initiate feed ID discovery.

    Args:
      topic: The feed's topic URL.
    """
    target_queue = MAPPINGS_QUEUE
    (0..RETRIES).each do |i|
      begin
        task = Task.create(:url => '/work/record_feeds', :params => {'topic' => topic})
        TaskQueue.add(target_queue, task)

        # todo - (barinek) check this...
        return
      rescue Error => e
        logger.error("Could not insert task to do feed ID "+
                "discovery for topic = #{topic}")
        if i == (RETRIES - 1)
          raise
        end
      end
    end

  end

  def self.create_key(topic)
    """Creates a key for a KnownFeed.

    Args:
      topic: The feed's topic URL.

    Returns:
      Key instance for this feed.
    """
    get_hash_key_name(topic)
  end

  def self.check_exists(topics)
    """Checks if the supplied topic URLs are known feeds.

    Args:
      topics: Iterable of topic URLs.

    Returns:
      List of topic URLs with KnownFeed entries. If none are known, this list
      will be empty. The returned order is arbitrary.
    """
    results = []
    topics.to_set.each do |topic |
      feed = get_by_key_name(create_key(topic))
      results.push feed.topic if feed
    end
    results.to_a
  end


  def <=> other
    other.key_name <=> key_name
    other.topic <=> topic
  end

end
