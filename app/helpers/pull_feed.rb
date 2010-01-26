class Main
  helpers do

    def pull_feed(feed_to_fetch, fetch_url, headers)
      """Pulls a feed.

      Args:
        feed_to_fetch: FeedToFetch instance to pull.
        fetch_url: The URL to fetch. Should be the same as the topic stored on
          the FeedToFetch instance, but may be different due to redirects.
        headers: Dictionary of headers to use for doing the feed fetch.

      Returns:
        Tuple (status_code, response_headers, content) where:
          status_code: The response status code.
          response_headers: Caseless dictionary of response headers.
          content: The body of the response.

      Raises:
        apiproxy_errors.Error if any RPC errors are encountered. urlfetch.Error if
        there are any fetching API errors.
      """
      uri = URI.parse(fetch_url)
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Get.new(uri.path)
      response = http.request(request)
      [response.code, response.headers, response.body]
    end

  end
end
