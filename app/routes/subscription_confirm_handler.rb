class Main
  """Background worker for asynchronously confirming subscriptions."""

  post "/work/subscriptions" do

    sub_key_name = request.get('subscription_key_name')
    next_state = request.get('next_state')
    verify_token = request.get('verify_token')
    secret = request.get('secret', nil)
    auto_reconfirm = !request.get('auto_reconfirm').nil?
    sub = Subscription.get_by_key_name(sub_key_name)
    unless sub
      logger.debug("No subscriptions to confirm "+
              "for subscription_key_name = #{sub_key_name}")
      return
    end

    if next_state.eql? Subscription::STATE_TO_DELETE
      mode = 'unsubscribe'
    else
      # NOTE: If next_state wasn't specified, this is probably an old task from
      # the last version of this code. Handle these tasks by assuming they
      # meant subscribe, which will probably cause less damage.
      mode = 'subscribe'
    end

    # todo - (barinek) remove this...
    if sub.subscription_state == Subscription::STATE_TO_DELETE
      logger.info('Skipping subscription pending delete')
      return
    end

    unless confirm_subscription(
            mode, sub.topic, sub.callback,
            verify_token, secret, sub.lease_seconds)
      # After repeated re-confirmation failures for a subscription, assume that
      # the callback is dead and archive it. End-user-initiated subscription
      # requests cannot possibly follow this code path, preventing attacks
      # from unsubscribing callbacks without ownership.
      confirm_failed = sub.confirm_failed(next_state, verify_token, auto_reconfirm, :secret=>secret)
      if (!confirm_failed and auto_reconfirm and mode.eql? 'subscribe')
        logger.info("Auto-renewal subscribe request failed the maximum " +
                "number of times for callback = #{sub.callback}, topic = #{sub.topic}; " +
                "subscription archived")
        Subscription.archive(sub.callback, sub.topic)
      end

    end

  end

end