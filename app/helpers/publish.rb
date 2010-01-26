class Main
  helpers do

    def publish(params = {})
      """End-user accessible handler for the Publish event."""

      response.headers['Content-Type'] = 'text/plain'

      mode = params['hub.mode']
      if !mode or mode.downcase != 'publish'
        halt [400, 'hub.mode MUST be "publish"']
      end

      # todo - (barinek) handle multiple hub.url params
      urls = params['hub.url']
      unless urls
        halt [400, 'MUST supply at least one hub.url parameter']
      end

      urls = urls.to_set

      logger.debug("Publish event for #{urls.size} URLs: #{urls}")
      receive_publish(urls, 204, 'hub.url')
    end

    def receive_publish(urls, success_code, param_name)
      """Receives a publishing event for a set of topic URLs.

      Serves 400 errors on invalid input, 503 retries on insertion failures.

      Args:
        urls: Iterable of URLs that have been published.
        success_code: HTTP status code to return on success.
        param_name: Name of the parameter that will be validated.

      Returns:
        The error message, or an empty string if there are no errors.
      """
      urls = preprocess_urls(urls)
      urls.each do |url|
        unless is_valid_url(url)
          halt 400, "#{param_name} invalid: #{url}"
        end
      end

      # Normalize all URLs. This assumes our web framework has already decoded
      # any POST-body encoded URLs that were passed in to the 'urls' parameter.
      urls = urls.collect do |url|
        normalize_iri(url)
      end

      # Only insert FeedToFetch entities for feeds that are known to have
      # subscribers. The rest will be ignored.
      topic_map = KnownFeedIdentity.derive_additional_topics(urls)
      unless topic_map.size > 0
        urls = Set.new
      else
        # Expand topic URLs by their feed ID to properly handle any aliases
        # this feed may have active subscriptions for.
        # TODO(bslatkin): Do something more intelligent here, like collate
        # all of these topics into a single feed fetch and push, instead of
        # one separately for each alias the feed may have.
        urls = Set.new
        topic_map.each do |topic, value|
          urls.merge value.to_a
        end
        #logger.info("Topics with known subscribers: #{urls.to_a.join(',')}")
      end

      source_dict = derive_sources(urls)

      # Record all FeedToFetch requests here. The background Pull worker will
      # double-check if there are any subscribers that need event delivery and
      # will skip any unused feeds.
      begin
        FeedToFetch.insert(urls, source_dict)
      rescue StandardError => e
        logger.error('Failed to insert FeedToFetch records')
        response.headers['Retry-After'] = '120'
        response.status = '503'
      end
      success_code
    end

  end
end