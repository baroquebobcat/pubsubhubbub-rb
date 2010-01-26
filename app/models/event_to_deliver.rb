class EventToDeliver < Ohm::Model
  include Comparable

  """Represents a publishing event to deliver to subscribers.

  This model is meant to be used together with Subscription entities. When a
  feed has new published data and needs to be pushed to subscribers, one of
  these entities will be inserted. The background worker should iterate
  through all Subscription entities for this topic, sending them the event
  payload. The update() method should be used to track the progress of the
  background worker as well as any Subscription entities that failed delivery.

  The key_name for each of these entities is unique. It is up to the event
  injection side of the system to de-dupe events to deliver. For example, when
  a publish event comes in, that publish request should be de-duped immediately.
  Later, when the feed puller comes through to grab feed diffs, it should insert
  a single event to deliver, collapsing any overlapping publish events during
  the delay from publish time to feed pulling time.
  """

  ATOM = 'atom'
  RSS = 'rss'

  DELIVERY_MODES = ['normal', 'retry']
  NORMAL = 'normal'
  RETRY = 'retry'

  EVENT_SUBSCRIBER_CHUNK_SIZE = 50

  attribute :key_name
  attribute :parent_key_name
  attribute :topic
  attribute :topic_hash
  attribute :payload
  attribute :last_callback
  attribute :failed_callbacks
  attribute :delivery_mode
  attribute :retry_attempts
  attribute :last_modified
  attribute :totally_failed
  attribute :content_type

  index :key_name

  def self.create(*args)
    model = super
    model.last_callback = '' unless model.last_callback
    model.delivery_mode = NORMAL unless model.delivery_mode
    model.retry_attempts = 0 unless model.retry_attempts
    model.totally_failed = false unless model.totally_failed
    model.content_type = '' unless model.content_type
    model.save
    model
  end

  def validate
    assert_unique :key_name
    assert_present :topic
    assert_present :topic_hash
    assert_present :payload
    assert_present :last_modified
  end

  def self.create_event_for_topic(topic, format, header_footer, entry_payloads, now = Time.now)
    """Creates an event to deliver for a topic and set of published entries.

    Args:
      topic: The topic that had the event.
      format: Format of the feed, either 'atom' or 'rss'.
      header_footer: The header and footer of the published feed into which
        the entry list will be spliced.
      entry_payloads: List of strings containing entry payloads (i.e., all
        XML data for each entry, including surrounding tags) in order of newest
        to oldest.
      now: Returns the current time as a UTC datetime. Used in tests.

    Returns:
      A new EventToDeliver instance that has not been stored.
    """
    close_tag, content_type = nil

    if format.eql? ATOM
      close_tag = '</feed>'
      content_type = 'application/atom+xml'
    elsif format.eql? RSS
      close_tag = '</channel>'
      content_type = 'application/rss+xml'
    else
      raise "Invalid format \"#{format}\""
    end


    prefix = header_footer.scan(/(.*?)#{close_tag}/m)
    prefix = prefix.first.first if prefix.size > 0
    payload_list = ['<?xml version="1.0" encoding="utf-8"?>', prefix]

    payload_list += (entry_payloads)
    payload_list << (close_tag)

    payload = payload_list.join('\n')

    parent_key_name = FeedRecord.create_key_name(topic);

    return EventToDeliver.create(:parent_key_name => parent_key_name,
                                 :topic => topic,
                                 :topic_hash => sha1_hash(topic),
                                 :payload => payload,
                                 :last_modified => Time.now,
                                 :content_type => content_type)
  end

  def get_next_subscribers(chunk_size = nil)
    """Retrieve the next set of subscribers to attempt delivery for this event.

    Args:
      chunk_size: How many subscribers to retrieve at a time while delivering
        the event. Defaults to EVENT_SUBSCRIBER_CHUNK_SIZE.

    Returns:
      Tuple (more_subscribers, subscription_list) where:
        more_subscribers: True if there are more subscribers to deliver to
          after the returned 'subscription_list' has been contacted; this value
          should be passed to update() after the delivery is attempted.
        subscription_list: List of Subscription entities to attempt to contact
          for this event.
    """
    unless chunk_size
      chunk_size = EVENT_SUBSCRIBER_CHUNK_SIZE
    end

    if delivery_mode == NORMAL
      all_subscribers = Subscription.get_subscribers(topic, chunk_size + 1, last_callback)
      if all_subscribers
        last_callback = all_subscribers.last.callback
      else
        last_callback = ''
      end

      more_subscribers = all_subscribers.size > chunk_size
      subscription_list = all_subscribers[0..chunk_size]
    elsif delivery_mode == RETRY

      # todo.....
#      next_chunk = self.failed_callbacks[:chunk_size]
#      more_subscribers = len(self.failed_callbacks) > len(next_chunk)
#
#      if self.last_callback:
#        # If the final index is present in the next chunk, that means we've
#        # wrapped back around to the beginning and will need to do more
#        # exponential backoff. This also requires updating the last_callback
#        # in the update() method, since we do not know which callbacks from
#        # the next chunk will end up failing.
#        final_subscription_key = datastore_types.Key.from_path(
#            Subscription.__name__,
#            Subscription.create_key_name(self.last_callback, self.topic))
#        try:
#          final_index = next_chunk.index(final_subscription_key)
#        except ValueError:
#          pass
#        else:
#          more_subscribers = False
#          next_chunk = next_chunk[:final_index]
#
#      subscription_list = [x for x in db.get(next_chunk) if x is not None]
#      if subscription_list and not self.last_callback:
#        # This must be the first time through the current iteration where we do
#        # not yet know a sentinal value in the list that represents the starting
#        # point.
#        self.last_callback = subscription_list[0].callback
#
#      # If the failed callbacks fail again, they will be added back to the
#      # end of the list.
#      self.failed_callbacks = self.failed_callbacks[len(next_chunk):]

    end

    return more_subscribers, subscription_list

  end

  # Maximum number of times to attempt to deliver a feed event.
  MAX_DELIVERY_FAILURES = 4

  # Period to use for exponential backoff on feed event delivery.
  DELIVERY_RETRY_PERIOD = 30 # seconds


  def update(more_callbacks, more_failed_callbacks, options = {})
    """Updates an event with work progress or deletes it if it's done.

    Reschedules another Task to run to handle this event delivery if needed.

    Args:
      more_callbacks: True if there are more callbacks to deliver, False if
        there are no more subscribers to deliver for this feed.
      more_failed_callbacks: Iterable of Subscription entities for this event
        that failed to deliver.
      max_failures: Maximum failures to allow before giving up.
      retry_period: Initial period for doing exponential (base-2) backoff.
      now: Returns the current time as a UTC datetime.
    """
    options = ({ :now => Time.now, :max_failures => MAX_DELIVERY_FAILURES, :retry_period => DELIVERY_RETRY_PERIOD}).merge(options)

    last_modified = options[:now]

    # Ensure the list of failed callbacks is in sorted order so we keep track
    # of the last callback seen in alphabetical order of callback URL hashes.
#    more_failed_callbacks = sorted(more_failed_callbacks,
#                                   key=lambda x: x.callback_hash)
#

    # todo - (barinek) fix this!!!
    more_failed_callbacks = more_failed_callbacks.sort

    failed_callbacks = []
    more_failed_callbacks.each do |e|
      failed_callbacks << e.key_name
    end


    if !more_callbacks and failed_callbacks.empty?
      logger.info("EventToDeliver complete: topic = #{topic}, delivery_mode = #{delivery_mode}")
      delete
      return
    elsif !more_callbacks
      # todo.....
#      self.last_callback = ''
#      retry_delay = retry_period * (2 ** self.retry_attempts)
#      self.last_modified += datetime.timedelta(seconds=retry_delay)
#      self.retry_attempts += 1
#      if self.retry_attempts > max_failures:
#        self.totally_failed = True
#
#      if self.delivery_mode == EventToDeliver.NORMAL:
#        logging.warning('Normal delivery done; %d broken callbacks remain',
#                        len(self.failed_callbacks))
#        self.delivery_mode = EventToDeliver.RETRY
#      else:
#        logging.warning('End of attempt %d; topic = %s, subscribers = %d, '
#                        'waiting until %s or totally_failed = %s',
#                        self.retry_attempts, self.topic,
#                        len(self.failed_callbacks), self.last_modified,
#                        self.totally_failed)
#
    end

    save

    if !totally_failed
      # TODO(bslatkin): Do this enqueuing transactionally.
      self.enqueue()
    end

  end

  RETRIES = 3
  EVENT_QUEUE = 'event-delivery'
  EVENT_RETRIES_QUEUE = 'event-delivery-retries'
  POLLING_QUEUE = 'polling'

  def enqueue
    """Enqueues a Task that will execute this EventToDeliver."""

    # TODO(bslatkin): Remove these retries when they're not needed in userland.

    if delivery_mode == EventToDeliver::RETRY
      target_queue = EVENT_RETRIES_QUEUE
    elsif ENV['HTTP_X_APPENGINE_QUEUENAME'] == POLLING_QUEUE
      target_queue = POLLING_QUEUE
    else
      target_queue = EVENT_QUEUE
    end

    (1..RETRIES).each do |i|
      begin
        task = Task.create(:url => '/work/push_events', :eta => last_modified, :params => {
                'event_key' => key_name
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

end