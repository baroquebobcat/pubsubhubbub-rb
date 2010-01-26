class Main
  """Background worker for cleaning up expired EventToDeliver instances."""

  EVENT_CLEANUP_MAX_AGE_SECONDS = (10 * 24 * 60 * 60) # 10 days

  get "/work/event_cleanup" do
#       todo...
#       threshold = (Time.now - EVENT_CLEANUP_MAX_AGE_SECONDS)
#       events = (EventToDeliver.all()
#                 .filter('totally_failed =', True)
#                 .filter('last_modified <=', threshold)
#                 .order('last_modified').fetch(EVENT_CLEANUP_CHUNK_SIZE))
#       if events:
#         logging.info('Cleaning up %d events older than %s',
#                      len(events), threshold)
#         try:
#           db.delete(events)
#         except (db.Error, apiproxy_errors.Error, runtime.DeadlineExceededError):
#           logging.exception('Could not clean-up EventToDeliver instances')
  end

end