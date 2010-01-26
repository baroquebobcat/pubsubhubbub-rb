class Main

  VALID_PORTS = ['80', '443', '4443', '8080', '8081', '8082', '8083', '8084', '8085', '8086', '8087', '8088', '8089', '8188', '8444', '8990', '3000']
  DEFAULT_LEASE_SECONDS = (30 * 24 * 60 * 60) # 30 days
  MAX_LEASE_SECONDS = DEFAULT_LEASE_SECONDS * 3 # 90 days

  helpers do

    def subscribe(params = {})
      """End-user accessible handler for Subscribe and Unsubscribe events."""

      response.headers['Content-Type'] = 'text/plain'

      callback = request.get('hub.callback', '')
      topic = request.get('hub.topic', '')

      # todo - (barinek) handle multiple hub.verify params
      verify_type_list = request.get_all('hub.verify').collect {|value| value.downcase}

      # todo - (barinek) handle unicode...
      verify_token = request.get('hub.verify_token', '')
      secret = request.get('hub.secret', '')
      lease_seconds = request.get('hub.lease_seconds',
                                  Subscription::DEFAULT_LEASE_SECONDS.to_s)
      mode = request.get('hub.mode', '').downcase

      error_message = nil
      if callback.blank? or !is_valid_url(callback)
        error_message = ("Invalid parameter: hub.callback; " +
                "must be valid URI with no fragment and " +
                "optional port #{VALID_PORTS.join(',')}")
      else
        callback = normalize_iri(callback)
      end

      if topic.blank? or !is_valid_url(topic)
        error_message = ("Invalid parameter: hub.topic; "+
                "must be valid URI with no fragment and " +
                "optional port #{VALID_PORTS.join(',')}")
      else
        topic = normalize_iri(topic)
      end

      enabled_types = []
      verify_type_list.each do |type|
        if ['async', 'sync'].include? type
          enabled_types.push type
        end
      end

      if enabled_types.empty?
        error_message = "Invalid values for hub.verify: #{verify_type_list}"
      else
        @verify_type = enabled_types[0]
      end

      unless ['subscribe', 'unsubscribe'].include? mode
        error_message = "Invalid value for hub.mode: #{mode}"
      end

      # todo - bit strange below...
      if lease_seconds
        begin
          old_lease_seconds = lease_seconds
          lease_seconds = old_lease_seconds.to_i
          if !(old_lease_seconds.eql? lease_seconds.to_s)
            raise StandardError
          end
        rescue StandardError:
          error_message = "Invalid value for hub.lease_seconds: #{old_lease_seconds}"
        end
      end

      if error_message
        logger.debug("Bad request for mode = #{mode}, topic = #{topic}, " +
                "callback = #{callback}, verify_token = #{verify_token}, lease_seconds = #{lease_seconds}: #{error_message}")
        response.status = '400'
        response.body = error_message
        return
      end

      begin
        # Retrieve any existing subscription for this callback.
        sub = Subscription.get_by_key_name(
                Subscription.create_key_name(callback, topic))

        # Deletions for non-existant subscriptions will be ignored.
        if mode.eql? 'unsubscribe' and sub.nil?
          response.status = '204'
          return
        end

        # Enqueue a background verification task, or immediately confirm.
        # We prefer synchronous confirmation.
        if @verify_type.eql? 'sync'
          if confirm_subscription(mode, topic, callback, verify_token, secret, lease_seconds)
            response.status = '204'
            return
          else
            response.body = 'Error trying to confirm subscription'
            response.status = '409'
            return
          end
        else
          if mode.eql? 'subscribe'
            Subscription.request_insert(callback, topic, verify_token, secret,
                                        :lease_seconds=>lease_seconds.to_i)
          else
            Subscription.request_remove(callback, topic, verify_token)
          end

          logger.debug("Queued #{mode} request for callback = #{callback}, "+
                  "topic = #{topic}, verify_token = \"#{verify_token}\", lease_seconds= #{lease_seconds}")
          response.status = '202'
          return
        end

      rescue StandardError => e
        logger.error('Could not verify subscription request')
        response.headers['Retry-After'] = '120'
        response.status = '503'
      end
    end

  end

end