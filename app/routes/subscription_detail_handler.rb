class Main
  """Handler that serves details about subscriber deliveries to end-users."""

  get "/subscription-details" do

    topic_url = normalize_iri(request.get('hub.topic'))
    callback_url = normalize_iri(request.get('hub.callback'))
    secret = normalize_iri(request.get('hub.secret'))
    subscription = Subscription.get_by_key_name(
            Subscription.create_key_name(callback_url, topic_url))

    @content = {
            'topic_url' => topic_url,
            'callback_url' => callback_url
    }

    if subscription.nil? or (subscription.secret and !(subscription.secret.eql? secret))
      session[:error] = "Could not find any subscription for " +
              "the given (callback, topic, secret) tuple"
    else

      # todo...
#      failed_events = (EventToDeliver.all()
#        .filter('failed_callbacks =', subscription.key())
#        .order('-last_modified')
#        .fetch(25))
      @context = ({
              'created_time' => subscription.created_time,
              'last_modified' => subscription.last_modified,
              'lease_seconds' => subscription.lease_seconds,
              'expiration_time' => subscription.expiration_time,
              'confirm_failures' => subscription.confirm_failures,
              'subscription_state' => subscription.subscription_state,
              'failed_events' => []
              #          {
              #            'last_modified': e.last_modified,
              #            'retry_attempts': e.retry_attempts,
              #            'totally_failed': e.totally_failed,
              #            'content_type': e.content_type,
              #            'payload_trunc': e.payload[:10000],
              #          }
              #          for e in failed_events]
      }).merge(@content)

    end
    haml :subscription_details

  end

end