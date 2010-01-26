class Main
  """Background worker for pulling feeds."""

  MAX_REDIRECTS = 7

  post '/work/pull_feeds' do

    topic = request.get('topic')
    work = FeedToFetch.get_by_topic(topic)

    unless work
      logger.debug("No feeds to fetch for topic = #{topic}")
      return
    end

    unless Subscription.has_subscribers(work.topic):
      logger.debug("Ignoring event because there are no subscribers "+
              "for topic #{work.topic}")
      # If there are no subscribers then we should also delete the record of
      # this being a known feed. This will clean up after the periodic polling.
      # TODO(bslatkin): Remove possibility of race-conditions here, where a
      # user starts subscribing to a feed immediately at the same time we do
      # this kind of pruning.
      if work.done
        known_feed = KnownFeed.get_by_key_name(KnownFeed.create_key(work.topic))
        known_feed.delete
        return
      end
    end

    status_code, headers, content = nil
    handled = false

    feed_record = FeedRecord.get_or_create(work.topic)
    fetch_url = work.topic

    (1..MAX_REDIRECTS).each do |redirect_count|
      logger.debug("Fetching feed at #{fetch_url}")
      begin
        status_code, headers, content = pull_feed(work, fetch_url, feed_record.get_request_headers)

        # todo - (barinek) - bring back with tests...
#        except urlfetch.ResponseTooLargeError:
#          logging.critical('Feed response too large for topic %s at url %s; '
#                           'skipping', work.topic, fetch_url)
#          work.done()
#          return
#        except (apiproxy_errors.Error, urlfetch.Error):
#          logging.exception('Failed to fetch feed')
#          work.fetch_failed()
#          return
#
      rescue StandardError => e
        logger.error('Failed to fetch feed', e)
        work.fetch_failed()
      end

      if status_code.eql? '200'
        break
      end

      if ['301', '302', '303', '307'].include? status_code and headers.include? 'Location'
        fetch_url = headers['Location']
        logger.debug("Feed publisher returned #{status_code} redirect to \"#{fetch_url}\"")
      elsif status_code.eql? '304'
        logger.debug('Feed publisher returned 304 response (cache hit)')
        work.done()
        handled = true
        break
      else
        logger.warn("Received bad status_code = #{status_code}, response_headers = #{headers}")
        work.fetch_failed()
        handled = true
        break
      end

      if redirect_count == MAX_REDIRECTS
        # This means we've done too many redirects and will fail this fetch.
        logger.warn('Too many redirects!')
        work.fetch_failed()
        handled = true
        break
      end

    end

    return if handled

    if parse_feed(feed_record, headers, content)
      work.done
    else
      work.fetch_failed
    end

  end

end
