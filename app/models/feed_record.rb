class FeedRecord < Ohm::Model
  include Comparable

  """Represents record of the feed from when it has been polled.

  This contains everything in a feed except for the entry data. That means any
  footers, top-level XML elements, namespace declarations, etc, will be
  captured in this entity.

  The key name of this entity is a get_hash_key_name() of the topic URL.
  """

  attribute :key_name
  attribute :topic
  attribute :header_footer # Save this for debugging.
  attribute :last_updated # The last polling time.

  list :entries

  # Content-related headers.
  attribute :content_type
  attribute :last_modified
  attribute :etag

  index :key_name

  def self.create(*args)
    model = super
    model.last_updated = Time.now unless model.last_updated
    model.save
    model
  end

  def validate
    assert_unique :key_name
    assert_present :topic
    #assert_present :last_updated # todo - fix this...
  end

  def self.create_key_name(topic)
    """Creates a key name for a FeedRecord for a topic.

    Args:
      topic: The topic URL for the FeedRecord.

    Returns:
      String containing the key name.
    """
    return get_hash_key_name(topic)
  end

  def self.get_or_create(topic)
    """Retrieves a FeedRecord by its topic or creates it if non-existent.

    Args:
      topic: The topic URL to retrieve the FeedRecord for.

    Returns:
      The FeedRecord found for this topic or a new one if it did not already
      exist.
    """
    return FeedRecord.get_or_insert(FeedRecord.create_key_name(topic), topic)
  end

  def self.get_or_insert(key_name, topic)
    feed_record = FeedRecord.get_by_key_name(key_name)
    unless feed_record
      feed_record = FeedRecord.create(:key_name=>key_name, :topic=>topic)
    end
    feed_record
  end

  def update(headers, header_footer = nil)
    """Updates the polling record of this feed.

    This method will *not* insert this instance into the Datastore.

    Args:
      headers: Dictionary of response headers from the feed that should be used
        to determine how to poll the feed in the future.
      header_footer: Contents of the feed's XML document minus the entry data;
        if not supplied, the old value will remain.
    """

    content_type = headers['Content-Type']
    content_type.downcase if content_type

    write_local(:content_type, content_type)
    write_local(:last_modified, headers['Last-Modified'])
    write_local(:etag, headers['ETag'])
    if !header_footer.nil?
      write_local(:header_footer, header_footer)
    end
    save
  end

  def get_request_headers
    """Returns the request headers that should be used to pull this feed.

    Returns:
      Dictionary of request header values.
    """
    headers = {
            'Cache-Control'=> 'no-cache no-store max-age=1',
            'Connection'=> 'cache-control',
            }
    if last_modified
      headers['If-Modified-Since'] = last_modified
    end

    if etag
      headers['If-None-Match'] = etag
    end
    headers
  end

end