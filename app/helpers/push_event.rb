class Main
  helpers do

    def push_event(sub, headers, payload)
      """Pushes an event to a single subscriber using an asynchronous API call.

      Args:
        sub: The Subscription instance to push the event to.
        headers: Request headers to use when pushing the event.
        payload: The content body the request should have.
        async_proxy: AsyncAPIProxy to use for registering RPCs.
        callback: Python callable to execute on success or failure. This callback
          has the signature func(sub, result, exception) where sub is the
          Subscription instance, result is the urlfetch.Response instance, and
          exception is any exception encountered, if any.
      """
      uri = URI.parse(sub.callback)
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Post.new(uri.path, headers)
      http.request(request, payload)
    end

  end
end
