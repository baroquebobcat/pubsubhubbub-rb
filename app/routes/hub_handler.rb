class Main
  """Handler to multiplex subscribe and publish events on the same URL."""

  get "/?" do
    haml :welcome
  end

  post "/?" do
    mode = request.get('hub.mode', '').downcase

    if mode.eql? 'publish'
      publish(params)
    elsif ['subscribe', 'unsubscribe'].include? mode
      subscribe(params)
    else
      halt 404, 'hub.mode is invalid'
    end

  end
end
