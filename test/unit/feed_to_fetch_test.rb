require File.dirname(__FILE__) + '/../test_helper'

class FeedToFetchTest < Test::Unit::TestCase

  setup do
    Ohm.flush
    @topic = 'http://example.com/topic-one'
    @topic2 = 'http://example.com/topic-two'
    @topic3 = 'http://example.com/topic-three'
  end

  should "testInsertAndGet" do
    """Tests inserting and getting work."""
    all_topics = [@topic, @topic2, @topic3]
    FeedToFetch.insert(all_topics)
    found_topics = (all_topics.collect {|topic| FeedToFetch.get_by_topic(topic).topic }).to_set
    tasks = TaskQueue.all(FeedToFetch::FEED_QUEUE)
    task_topics = tasks.each.collect { |task| task.params['topic'] }.to_set
    assertEquals(found_topics, task_topics)

    found_topics.each do |topic|
      feed_to_fetch = FeedToFetch.get_by_topic(topic)
      assertEquals(topic, feed_to_fetch.topic)
      assertEquals([], feed_to_fetch.source_keys)
      assertEquals([], feed_to_fetch.source_values)
    end

  end

  should "testEmpty" do
    """Tests when the list of urls is empty."""
    FeedToFetch.insert([])
    assertEquals([],  TaskQueue.all(FeedToFetch::FEED_QUEUE))

  end

  should "testDuplicates" do
    """Tests duplicate urls."""
    all_topics = [@topic, @topic, @topic2, @topic2]
    FeedToFetch.insert(all_topics)
    found_topics = (all_topics.collect {|topic| FeedToFetch.get_by_topic(topic).topic }).to_set
    assertEquals(all_topics.to_set, found_topics)

    tasks = TaskQueue.all(FeedToFetch::FEED_QUEUE)
    task_topics = tasks.each.collect { |task| task.params['topic'] }.to_set
    assertEquals(found_topics, task_topics)

  end

  should "testDone" do
    FeedToFetch.insert([@topic])
    feed = FeedToFetch.get_by_topic(@topic)
    assertTrue(feed.done())
    assertTrue(FeedToFetch.get_by_topic(@topic).nil?)
  end

  should "testDoneConflict" do
    """Tests when another entity was written over the top of this one."""
    FeedToFetch.insert([@topic])
    feed = FeedToFetch.get_by_topic(@topic)
    FeedToFetch.insert([@topic])
    assertFalse(feed.done())
    assertTrue(!FeedToFetch.get_by_topic(@topic).nil?)
  end

  # todo...

#  def testFetchFailed(self):
#    start = datetime.datetime.utcnow()
#    now = lambda: start
#
#    FeedToFetch.insert([self.topic])
#    etas = []
#    for i, delay in enumerate((5, 10, 20, 40, 80)):
#      feed = FeedToFetch.get_by_topic(self.topic)
#      feed.fetch_failed(max_failures=5, retry_period=5, now=now)
#      expected_eta = start + datetime.timedelta(seconds=delay)
#      self.assertEquals(expected_eta, feed.eta)
#      etas.append(testutil.task_eta(feed.eta))
#      self.assertEquals(i+1, feed.fetching_failures)
#      self.assertEquals(False, feed.totally_failed)
#
#    feed.fetch_failed(max_failures=5, retry_period=5, now=now)
#    self.assertEquals(True, feed.totally_failed)
#
#    tasks = testutil.get_tasks(main.FEED_QUEUE, expected_count=1)
#    tasks.extend(testutil.get_tasks(main.FEED_RETRIES_QUEUE, expected_count=5))
#    found_etas = [t['eta'] for t in tasks[1:]]  # First task is from insert()
#    self.assertEquals(etas, found_etas)
#
#  def testQueuePreserved(self):
#    """Tests the request's polling queue is preserved for new FeedToFetch."""
#    FeedToFetch.insert([self.topic])
#    feed = FeedToFetch.all().get()
#    testutil.get_tasks(main.FEED_QUEUE, expected_count=1)
#    feed.delete()
#
#    os.environ['HTTP_X_APPENGINE_QUEUENAME'] = main.POLLING_QUEUE
#    try:
#      FeedToFetch.insert([self.topic])
#      feed = FeedToFetch.all().get()
#      testutil.get_tasks(main.FEED_QUEUE, expected_count=1)
#      testutil.get_tasks(main.POLLING_QUEUE, expected_count=1)
#    finally:
#      del os.environ['HTTP_X_APPENGINE_QUEUENAME']
#
#  def testSources(self):
#    """Tests when sources are supplied."""
#    source_dict = {'foo': 'bar', 'meepa': 'stuff'}
#    all_topics = [self.topic, self.topic2, self.topic3]
#    FeedToFetch.insert(all_topics, source_dict=source_dict)
#    for topic in all_topics:
#      feed_to_fetch = FeedToFetch.get_by_topic(topic)
#      self.assertEquals(topic, feed_to_fetch.topic)
#      found_source_dict = dict(zip(feed_to_fetch.source_keys,
#                                   feed_to_fetch.source_values))
#      self.assertEquals(source_dict, found_source_dict)
#

end