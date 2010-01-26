class FeedEntryRecord < Ohm::Model
  include Comparable

  """Represents a feed entry that has been seen.

  The key name of this entity is a get_hash_key_name() hash of the combination
  of the topic URL and the entry_id.
  """
  attribute :key_name
  attribute :parent_key_name
  attribute :entry_id
  attribute :entry_id_hash
  attribute :entry_content_hash
  attribute :update_time

  index :key_name

  def self.create(*args)
    model = super
    model.update_time = Time.now unless model.update_time
    model.save
    model
  end

  def validate
    assert_unique :key_name
    assert_present :entry_id
    assert_present :entry_id_hash
    #assert_present :update_time # todo - fix this...
  end

  def self.create_key(topic, entry_id)
    """Creates a new Key for a FeedEntryRecord entity.

    Args:
      topic: The topic URL to retrieve entries for.
      entry_id: String containing the entry_id.

    Returns:
      Key instance for this FeedEntryRecord.
    """
    key_name = get_hash_key_name(entry_id)
    feed_record = FeedRecord.get_by_key_name(FeedRecord.create_key_name(topic))
    feed_record.entries.add(key_name) if feed_record
    key_name
  end

  def self.get_entries_for_topic(topic, entry_id_list)
    """Gets multiple FeedEntryRecord entities for a topic by their entry_ids.

    Args:
      topic: The topic URL to retrieve entries for.
      entry_id_list: Sequence of entry_ids to retrieve.

    Returns:
      List of FeedEntryRecords that were found, if any.
    """
    keys = entry_id_list.each.collect do |entry_id|
      create_key(topic, entry_id)
    end

    results = [].to_set
    keys.each do |key_name|
      record = FeedEntryRecord.find(:key_name => key_name).first
      results << record unless record.nil?
    end
    results

  end

  def self.create_entry_for_topic(topic, entry_id, content_hash)
    """Creates multiple FeedEntryRecords entities for a topic.

    Does not actually insert the entities into the Datastore. This is left to
    the caller so they can do it as part of a larger batch put().

    Args:
      topic: The topic URL to insert entities for.
      entry_id: String containing the ID of the entry.
      content_hash: Sha1 hash of the entry's entire XML content. For example,
        with Atom this would apply to everything from <entry> to </entry> with
        the surrounding tags included. With RSS it would be everything from
        <item> to </item>.

    Returns:
      A new FeedEntryRecord that should be inserted into the Datastore.
    """

    key_name = create_key(topic, entry_id)
    parent = FeedRecord.get_by_key_name(entry_id)
    return FeedEntryRecord.create(:key_name => key_name,
                                  :parent_key_name => (parent.key_name if parent),
                                  :entry_id => entry_id,
                                  :entry_id_hash => sha1_hash(entry_id),
                                  :entry_content_hash => content_hash)
  end

end