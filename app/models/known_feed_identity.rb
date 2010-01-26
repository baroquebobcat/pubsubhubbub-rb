class KnownFeedIdentity < Ohm::Model
  include Comparable

  """Stores a set of known URL aliases for a particular feed."""

  attribute :key_name
  attribute :feed_id
  attribute :update_time

  set :topics

  index :key_name

  def validate
    assert_unique :key_name
  end

  def self.create_key(feed_id)
    """Creates a key for a KnownFeedIdentity.

    Args:
      feed_id: The feed's identity. For Atom this is the //feed/id element;
        for RSS it is the //rss/channel/link element. If for whatever reason
        the ID is missing, then the feed URL itself should be used.

    Returns:
      Key instance for this feed identity.
    """
    get_hash_key_name(feed_id)
  end

  def self.update(feed_id, topic)
    """Updates a KnownFeedIdentity to have a topic URL mapping.

    Args:
      feed_id: The identity of the feed to update with the mapping.
      topic: The topic URL to add to the feed's list of aliases.

    Returns:
      The KnownFeedIdentity that has been created or updated.
    """
    known_feed = get_by_key_name(create_key(feed_id))
    unless known_feed
      known_feed = KnownFeedIdentity.create(:feed_id=>feed_id, :key_name=>get_hash_key_name(feed_id))
    end
    if !known_feed.topics.include? topic
      known_feed.topics << topic
    end
    known_feed
  end

  def self.remove(feed_id, topic)
    """Updates a KnownFeedIdentity to no longer have a topic URL mapping.

    Args:
      feed_id: The identity of the feed to update with the mapping.
      topic: The topic URL to remove from the feed's list of aliases.

    Returns:
      The KnownFeedIdentity that has been updated or None if the mapping
      did not exist previously or has now been deleted because it has no
      active mappings.
    """
    known_feed = get_by_key_name(create_key(feed_id))

    return nil unless known_feed

    return nil if !known_feed.topics.delete(topic)

    if known_feed.topics.empty?
      known_feed.delete
      return nil
    else
      known_feed.save
      return known_feed
    end

  end

  def self.derive_additional_topics(topics)
    """Derives topic URL aliases from a set of topics by using feed IDs.

    If a topic URL has a KnownFeed entry but no valid feed_id or
    KnownFeedIdentity record, the input topic will be echoed in the output
    dictionary directly. This properly handles the case where the feed_id has
    not yet been recorded for the feed.

    Args:
      topics: Iterable of topic URLs.

    Returns:
      Dictionary mapping input topic URLs to their full set of aliases,
      including the input topic URL.
    """
    topics = topics.to_set
    output_dict = {}
    known_feeds = topics.collect do |topic|
      KnownFeed.get_by_key_name(KnownFeed.create_key(topic))
    end

    topics = []
    feed_ids = []
    known_feeds.each do |feed|
      next if feed.nil?

      fix_feed_id = feed.feed_id
      unless fix_feed_id.nil?
        fix_feed_id = fix_feed_id.strip
      end

      # No expansion for feeds that have no known topic -> feed_id relation, but
      # record those with KnownFeed as having a mapping from topic -> topic for
      # backwards compatibility with existing production data.
      unless fix_feed_id.blank?
        topics.push feed.topic
        feed_ids.push feed.feed_id
      else
        output_dict[feed.topic] = [feed.topic].to_set
      end

    end

    known_feed_ids = feed_ids.each.collect do |feed_id|
      get_by_key_name(create_key(feed_id))
    end

    topics.zip(known_feed_ids).each do | known_topic, identified |
      if identified
        unless output_dict[known_topic]
          output_dict[known_topic] = Set.new
        end
        identified.topics.each do |topic|
          output_dict[known_topic].add topic
        end
      end
    end

    output_dict

  end

end
