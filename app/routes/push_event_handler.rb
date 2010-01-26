class Main
  """Background worker for pushing events to subscribers."""

  post '/work/push_events' do

    work = EventToDeliver.get_by_key_name(request.get('event_key'))
    unless work
      logger.debug('No events to deliver.')
      return
    end

    # Retrieve the first N + 1 subscribers; note if we have more to contact.
    more_subscribers, subscription_list = work.get_next_subscribers()
    logger.info("#{subscription_list.size} more subscribers to contact for: " +
            "topic = #{work.topic}, delivery_mode = #{work.topic}")

    # Keep track of successful callbacks. Do this instead of tracking broken
    # callbacks because the asynchronous API calls could be interrupted by a
    # deadline error. If that happens we'll want to mark all outstanding
    # callback urls as still pending.

    failed_callbacks = subscription_list.to_set

#    def callback(sub, result, exception):
#      if exception or result.status_code not in (200, 204):
#        logging.warning('Could not deliver to target url %s: '
#                        'Exception = %r, status_code = %s',
#                        sub.callback, exception,
#                        getattr(result, 'status_code', 'unknown'))
#      else:
#        failed_callbacks.remove(sub)
#
#    def create_callback(sub):
#      return lambda *args: callback(sub, *args)
#
    payload_utf8 = utf8encoded(work.payload)
    subscription_list.each do |sub|
      headers = {
              # TODO(bslatkin): Remove the 'or' here once migration is done.
              'Content-Type' => work.content_type || 'text/xml',
              # XXX(bslatkin): add a better test for verify_token here.
              'X-Hub-Signature' => "sha1=#{EventToDeliver.sha1_hmac(sub.secret || sub.verify_token || '', payload_utf8)}",
              }

#      todo - (barinek) implement async proxy
#      hooks.execute(push_event,
#          sub, headers, payload_utf8, async_proxy, create_callback(sub))

      response = push_event(sub, headers, payload_utf8)

      if ['200', '204'].include? response.code
        failed_callbacks.delete(sub)
      end

    end

#    todo - (barinek) implement connection timeout
#    try:
#      async_proxy.wait()
#    except runtime.DeadlineExceededError:
#      logging.error('Could not finish all callbacks due to deadline. '
#                    'Remaining are: %r', [s.callback for s in failed_callbacks])

    work.update(more_subscribers, failed_callbacks)

  end
end
