class Main
  """End-user accessible handler for the Publish event."""

  get "/publish" do
    haml :publish_debug
  end

  post "/publish" do
    publish(params)
  end

end