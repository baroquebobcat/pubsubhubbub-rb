class Main

  ATOM = 'atom'
  RSS = 'rss'
  MAX_NEW_FEED_ENTRY_RECORDS = 200

  helpers do

    def parse_feed(feed_record, headers, content)
      """Parses a feed's content, determines changes, enqueues notifications.

      This function will only enqueue new notifications if the feed has changed.

      Args:
        feed_record: The FeedRecord object of the topic that has new content.
        headers: Dictionary of response headers found during feed fetching (may
            be empty).
        content: The feed document possibly containing new entries.

      Returns:
        True if successfully parsed the feed content; False on error.
      """

      entities_to_save, entry_payloads = []
      header_footer, format = nil

      # The content-type header is extremely unreliable for determining the feed's
      # content-type. Using a regex search for "<rss" could work, but an RE is
      # just another thing to maintain. Instead, try to parse the content twice
      # and use any hints from the content-type as best we can. This has
      # a bias towards Atom content (let's cross our fingers!).
      # TODO(bslatkin): Do something more efficient.

      content_type = feed_record.content_type ? feed_record.content_type : ''
      if content_type.include? 'rss'
        order = [RSS, ATOM]
      else
        order = [ATOM, RSS]
      end

      parse_failures = 0
      order.each do |format|
        # Parse the feed. If this fails we will give up immediately.
        begin
          header_footer, entities_to_save, entry_payloads = FindFeedUpdates.new.find_feed_updates(feed_record.topic, format, content)
          @format = format
          break
        rescue StandardError => e
          @error_traceback = e.message
          logger.debug("Could not get entries for content #{content} of #{content.size} bytes in format \"#{format}\":\n#{@error_traceback}")
          parse_failures += 1
        end
      end

      if parse_failures == order.size
        logger.error("Could not parse feed; giving up:\n#{@error_traceback}")
        # That's right, we return True. This will cause the fetch to be
        # abandoned on parse failures because the feed is beyond hope!
        return true
      end

      # If we have more entities than we'd like to handle, only save a subset of
      # them and force this task to retry as if it failed. This will cause two
      # separate EventToDeliver entities to be inserted for the feed pulls, each
      # containing a separate subset of the data.

      # todo - (barinek) bring back with tests...
      if false
#      if entities_to_save.size > MAX_NEW_FEED_ENTRY_RECORDS
#        logger.warning("Found more entities than we can process for topic #{feed_record.topic}; splitting")
#        entities_to_save = entities_to_save[0..MAX_NEW_FEED_ENTRY_RECORDS]
#        entry_payloads = entry_payloads[0..MAX_NEW_FEED_ENTRY_RECORDS]
        @parse_successful = false
      else
        feed_record.update(headers, header_footer)
        @parse_successful = true
      end

      if entities_to_save.size == 0
        logger.debug('No new entries found')
        event_to_deliver = nil
      else
        logger.info("Saving #{entities_to_save.size} new/updated entries")
        event_to_deliver = EventToDeliver.create_event_for_topic(
                feed_record.topic, @format, header_footer, entry_payloads)
      end

      # todo - (barinek) bring back with tests...
      # Segment all entities into smaller groups to reduce the chance of memory
      # errors or too large of requests when the entities are put in a single
      # call to the Datastore API.
#      all_entities = []
#      STEP = MAX_FEED_RECORD_SAVES
#      for position in xrange(0, len(entities_to_save), STEP):
#        next_entities = entities_to_save[position:position+STEP]
#        all_entities.append(next_entities)

      # todo - (barinek) bring back with tests...
      # Doing this put in a transaction ensures that we have written all
      # FeedEntryRecords, updated the FeedRecord, and written the EventToDeliver
      # at the same time. Otherwise, if any of these fails individually we could
      # drop messages on the floor. If this transaction fails, the whole fetch
      # will be redone and find the same entries again (thus it is idempotent).
#      def txn():
#        while all_entities:
#          group = all_entities.pop(0)
#          try:
#            db.put(group)
#          except (db.BadRequestError, apiproxy_errors.RequestTooLargeError):
#            logging.exception('Could not insert %d entities; splitting in half',
#                              len(group))
#            # Insert the first half at the beginning since we need to make sure that
#            # the EventToDeliver gets inserted first.
#            all_entities.insert(0, group[len(group)/2:])
#            all_entities.insert(0, group[:len(group)/2])
#            raise
#
#      for i in xrange(PUT_SPLITTING_ATTEMPTS):
#        try:
#          db.run_in_transaction(txn)
#          break
#        except (db.BadRequestError, apiproxy_errors.RequestTooLargeError):
#          pass
#      else:
#        logging.critical('Insertion of event to delivery *still* failing due to '
#                         'request size; dropping event for %s', feed_record.topic)
#        return True

      # TODO(bslatkin): Make this transactional with the call to work.done()
      # that happens in the PullFeedHandler.post() method.
      if event_to_deliver
        event_to_deliver.enqueue()
      end

      # Inform any hooks that there will is a new event to deliver that has
      # been recorded and delivery has begun.
      inform_event(event_to_deliver)

      @parse_successful
    end

  end
end
