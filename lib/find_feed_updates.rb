require 'digest/sha1'

class FindFeedUpdates

  # Maximum number of FeedEntryRecord entries to look up in parallel.
  MAX_FEED_ENTRY_RECORD_LOOKUPS = 500

  def find_feed_updates(topic, format, feed_content) # , filter_feed=feed_diff.filter):
    """Determines the updated entries for a feed and returns their records.

      Args:
        topic: The topic URL of the feed.
        format: The string 'atom' or 'rss'.
        feed_content: The content of the feed, which may include unicode characters.
        filter_feed: Used for dependency injection.

      Returns:
        Tuple (header_footer, entry_list, entry_payloads) where:
          header_footer: The header/footer data of the feed.
          entry_list: List of FeedEntryRecord instances, if any, that represent
            the changes that have occurred on the feed. These records do *not*
            include the payload data for the entry.
          entry_payloads: List of strings containing entry payloads (i.e., the XML
            data for the Atom <entry> or <item>).

      Raises:
        xml.sax.SAXException if there is a parse error.
        feed_diff.Error if the feed could not be diffed for any other reason.
      """
    header_footer, entries_map = FeedDiff.new.filter(feed_content, format)

    # Find the new entries we've never seen before, and any entries that we
    # knew about that have been updated.
    step = MAX_FEED_ENTRY_RECORD_LOOKUPS
    all_keys = entries_map.keys
    existing_entries = []

#      todo - (barinek) chunk this...
#      for position in xrange(0, len(all_keys), STEP):
#        key_set = all_keys[position:position+STEP]
#        existing_entries.extend(FeedEntryRecord.get_entries_for_topic(
#            topic, key_set))

    all_keys.each do |key|
      record = FeedEntryRecord.get_entries_for_topic(topic, key)
      existing_entries += record.to_a
    end
    
    existing_dict = {}
    existing_entries.each do |e|
      existing_dict[e.entry_id] = e.entry_content_hash
    end
    
    logger.info("Retrieved #{entries_map.size} feed entries, #{existing_dict.size} of which have been seen before")

    entities_to_save = []
    entry_payloads = []
    entries_map.each do |entry_id, new_content |
      new_content_hash = sha1_hash(new_content)
      # Mark the entry as new if the sha1 hash is different.
      begin
        old_content_hash = existing_dict[entry_id]
        if old_content_hash == new_content_hash
          next
        end
      rescue StandardError => e
        break
      end

      entry_payloads << (new_content)
      entities_to_save << (FeedEntryRecord.create_entry_for_topic(
              topic, entry_id, new_content_hash))

    end

    return header_footer, entities_to_save, entry_payloads

  end

  def sha1_hash(value)
    Digest::SHA1.hexdigest(value)
  end

end