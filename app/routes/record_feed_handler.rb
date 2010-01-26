class Main
  """Background worker for categorizing/classifying feed URLs by their ID."""

  FEED_IDENTITY_UPDATE_PERIOD = (10 * 24 * 60 * 60) # 10 days

  post '/work/record_feeds' do

    topic = request.get('topic')
    logger.debug("Recording topic = #{topic}")

    known_feed_key = KnownFeed.create_key(topic)
    known_feed = KnownFeed.get_by_key_name(known_feed_key)
    if known_feed
      seconds_since_update = Time.now.to_f - known_feed.update_time.to_f
      if known_feed.feed_id and (seconds_since_update < FEED_IDENTITY_UPDATE_PERIOD)
        logger.debug("Ignoring feed identity update for topic = #{topic} " +
                "due to update#{seconds_since_update} ago")
        return
      end
    else
      known_feed = KnownFeed.create(:topic => topic)
    end

    begin
      uri = URI.parse(topic)
      http = Net::HTTP.new(uri.host, uri.port)
      path = uri.path
      path += '?' + uri.query if uri.query # todo - remove...
      request = Net::HTTP::Get.new(path)
      response = http.request(request)

    rescue StandardError => e
      logger.error("Could not fetch topic = #{topic} for feed ID", e)
      return
    end

    # TODO(bslatkin): Add more intelligent retrying of feed identification.
    if !response.code.eql? '200'
      logger.warn("Fetching topic = #{topic} for feed ID returned response #{response.code}")
      return
    end

    feed_id, error_traceback = nil

    order = [ATOM, RSS]
    parse_failures = 0
    order.each do |feed_type|
      begin
        feed_id = FeedIdentifier.new.identify(response.body, feed_type)
        if !feed_id.nil?
          break
        else
          parse_failures += 1
          error_traceback = 'Could not determine feed_id'
        end

      rescue StandardError => e
        error_traceback = e.message
        logger.debug(
                "Could not parse feed for content of #{response.body.size} bytes in format \"#{feed_type}\":\n#{error_traceback}")
        parse_failures += 1
      end
    end

    if parse_failures == order.size or feed_id.nil?
      logger.warn("Could not record feed ID for topic = #{topic}:\n#{error_traceback}")
      return
    end

    logger.info("For topic = #{topic} found new feed ID #{feed_id}; old feed ID was #{known_feed.feed_id}")

    if known_feed.feed_id and (known_feed.feed_id != feed_id)
      logger.info("Removing old feed_id relation from " +
              "topic = #{topic} to feed_id = #{known_feed.feed_id}")
      KnownFeedIdentity.remove(known_feed.feed_id, topic)
    end

    KnownFeedIdentity.update(feed_id, topic)
    known_feed.feed_id = feed_id
    known_feed.save

  end

end