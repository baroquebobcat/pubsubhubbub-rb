class Main
  """Handler that serves topic debugging information to end-users."""

  get '/topic-details' do

    topic_url = normalize_iri(request.get('hub.url'))
    feed = FeedRecord.get_by_key_name(FeedRecord.create_key_name(topic_url))

    unless feed
      response.status = '400'
      @context = {
              'topic_url' => topic_url,
              'error' => 'Could not find any record for topic URL: ' + topic_url,
              }
      session[:error] = "Could not find any record for topic URL: " + topic_url
    else
      @context = {
              'topic_url' => topic_url,
              'last_successful_fetch' => feed.last_updated,
              'last_content_type' => feed.content_type,
              'last_etag' => feed.etag,
              'last_modified' =>feed.last_modified,
              'last_header_footer' => feed.header_footer,
              }
      fetch = FeedToFetch.get_by_topic(topic_url)
      if fetch
        @context = ({
                'next_fetch' => fetch.eta,
                'fetch_attempts' => fetch.fetching_failures,
                'totally_failed' => fetch.totally_failed,
                }).merge(@context)
      end
    end
    haml :topic_details

  end

end