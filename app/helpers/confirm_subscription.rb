class Main
  helpers do

    def confirm_subscription(mode, topic, callback, verify_token, secret, lease_seconds)
      """Confirms a subscription request and updates a Subscription instance.

      Args:
        mode: The mode of subscription confirmation ('subscribe' or 'unsubscribe').
        topic: URL of the topic being subscribed to.
        callback: URL of the callback handler to confirm the subscription with.
        verify_token: Opaque token passed to the callback.
        secret: Shared secret used for HMACs.
        lease_seconds: Number of seconds the client would like the subscription
          to last before expiring. If more than max_lease_seconds, will be capped
          to that value. Should be an integer number.

      Returns:
        True if the subscription was confirmed properly, False if the subscription
        request encountered an error or any other error has hit.
      """
      logger.debug("Attempting to confirm #{mode} for topic = #{topic}, callback = #{callback}, verify_token = #{verify_token}, secret = #{secret}, lease_seconds = #{lease_seconds}")

      parsed_url = URI(utf8encoded(callback))

      challenge = get_random_challenge()
      real_lease_seconds = [lease_seconds.to_i, MAX_LEASE_SECONDS].min
      params = {
              'hub.mode' => mode,
              'hub.topic'=> utf8encoded(topic),
              'hub.challenge'=> challenge,
              'hub.lease_seconds'=> real_lease_seconds,
              }
      if verify_token
        params['hub.verify_token'] = utf8encoded(verify_token)
      end

      begin
        http = Net::HTTP.new(parsed_url.host, parsed_url.port)
        response = http.request(params)

      rescue StandardError => e
        logger.error("Error encountered while confirming subscription", e)
        return false
      end

      if 200 <= response.code.to_i and response.code.to_i < 300 and response.body.eql? challenge
        if mode.eql? 'subscribe'
          # todo -  (barinek) check args...
          Subscription.insert(callback, topic, verify_token, secret, :lease_seconds=>real_lease_seconds)
          # Enqueue a task to record the feed and do discovery for it's ID.
          KnownFeed.record(topic)
        else
          Subscription.remove(callback, topic)
        end
        logger.info("Subscription action verified, callback = #{callback}, topic = #{topic}: #{mode}")
        return true

      elsif mode.eql? 'subscribe' and response.code.to_i == 404
        Subscription.archive(callback, topic)
        logger.info("Subscribe request returned 404 for callback = #{callback}, topic = #{topic}; subscription archived")
        return true
      else
        logger.warn("Could not confirm subscription; encountered status #{response.code} with content: #{response.body}" )
        return false
      end

    end

  end
end
    