class Main

  get "/subscribe" do
    haml :subscribe_debug
  end

  post "/subscribe" do
    subscribe(params)
  end

end