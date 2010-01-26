require File.dirname(__FILE__) + '/../test_helper'

class KnownFeedIdentityTest < Test::Unit::TestCase
  """Tests for the KnownFeedIdentity class."""

  setup do
    Ohm.flush

    @feed_id = 'my;feed;id'
    @feed_id2 = 'my;feed;id;2'
    @topic = 'http://example.com/foobar1'
    @topic2 = 'http://example.com/meep2'
    @topic3 = 'http://example.com/stuff3'
    @topic4 = 'http://example.com/blah4'
    @topic5 = 'http://example.com/woot5'
    @topic6 = 'http://example.com/neehaw6'
  end

  should "testUpdate" do
    """Tests the update method."""
    feed = KnownFeedIdentity.update(@feed_id, @topic)
    feed_key = KnownFeedIdentity.create_key(@feed_id)
    assert_equal feed_key, feed.key_name
    assert_equal @feed_id, feed.feed_id
    assert_equal [@topic], feed.topics.all

    feed = KnownFeedIdentity.update(@feed_id, @topic2)
    assert_equal @feed_id, feed.feed_id
    assert feed.topics.include? @topic
    assert feed.topics.include? @topic2
  end

  should "testRemove" do
    """Tests the remove method."""
    # Removing a mapping from an unknown ID does nothing.
    assert KnownFeedIdentity.remove(@feed_id, @topic).nil?

    KnownFeedIdentity.update(@feed_id, @topic)
    KnownFeedIdentity.update(@feed_id, @topic2)

    # Removing an unknown mapping for a known ID does nothing.
    assert KnownFeedIdentity.remove(@feed_id, @topic3).nil?

    # Removing from a known ID returns the updated copy.
    feed = KnownFeedIdentity.remove(@feed_id, @topic2)
    assert_equal([@topic], feed.topics)

    # Removing a second time does nothing.
    assert KnownFeedIdentity.remove(@feed_id, @topic2).nil?
    feed = KnownFeedIdentity.get_by_key_name(KnownFeedIdentity.create_key(@feed_id))
    assert_equal([@topic], feed.topics)

    # Removing the last one will delete the mapping completely.
    assert KnownFeedIdentity.remove(@feed_id, @topic).nil?
    feed = KnownFeedIdentity.get_by_key_name(KnownFeedIdentity.create_key(@feed_id))
    assert feed.nil?

  end

  should "testDeriveAdditionalTopics" do
    """Tests the derive_additional_topics method."""
    # topic, topic2 -> feed_id
    [@topic, @topic2].each do |topic|
      feed = KnownFeed.create_with_key_name(:topic=>topic)
      feed.feed_id = @feed_id
      feed.save
    end

    KnownFeedIdentity.update(@feed_id, @topic)
    KnownFeedIdentity.update(@feed_id, @topic2)

    # topic3, topic4 -> feed_id2
    [@topic3, @topic4].each do |topic|
      feed = KnownFeed.create_with_key_name(:topic=>topic)
      feed.feed_id = @feed_id2
      feed.save
    end

    KnownFeedIdentity.update(@feed_id2, @topic3)
    KnownFeedIdentity.update(@feed_id2, @topic4)

    # topic5 -> KnownFeed missing; should not be expanded at all
    # topic6 -> KnownFeed where feed_id = None; default to simple mapping
    KnownFeed.create_with_key_name(:topic=>@topic6)

    # Put missing topics first to provoke potential ordering errors in the
    # iteration order of the retrieval loop.
    result = KnownFeedIdentity.derive_additional_topics([
            @topic5, @topic6, @topic,
            @topic2, @topic3, @topic4])

    expected = {
            'http://example.com/foobar1' =>
                    ['http://example.com/foobar1', 'http://example.com/meep2'].to_set,
            'http://example.com/meep2' =>
                    ['http://example.com/foobar1', 'http://example.com/meep2'].to_set,
            'http://example.com/blah4' =>
                    ['http://example.com/blah4', 'http://example.com/stuff3'].to_set,
            'http://example.com/neehaw6' =>
                    ['http://example.com/neehaw6'].to_set,
            'http://example.com/stuff3' =>
                    ['http://example.com/blah4', 'http://example.com/stuff3'].to_set
    }
    assert_equal(expected, result)

  end

  should "testDeriveAdditionalTopicsWhitespace" do
    """Tests when the feed ID contains whitespace it is handled correctly.

    This test is only required because the 'feed_identifier' module did not
    properly strip whitespace in its initial version.
    """
    # topic -> feed_id with whitespace
    feed = KnownFeed.create_with_key_name(:topic=>@topic)
    feed.feed_id = @feed_id
    feed.save
    KnownFeedIdentity.update(@feed_id, @topic)

    # topic2 -> feed_id without whitespace
    feed = KnownFeed.create_with_key_name(:topic=>@topic2)
    feed.feed_id = "\n #{@feed_id} \n \n"
    feed.save
    KnownFeedIdentity.update(@feed_id, @topic2)

    # topic3 -> KnownFeed where feed_id = all whitespace
    feed = KnownFeed.create_with_key_name(:topic=>@topic3)
    feed.feed_id = "\n \n \n"
    feed.save

    result = KnownFeedIdentity.derive_additional_topics([
            @topic, @topic2, @topic3])

    expected = {
            'http://example.com/foobar1' =>
                    ['http://example.com/foobar1', 'http://example.com/meep2'].to_set,
            'http://example.com/stuff3' =>
                    ['http://example.com/stuff3'].to_set,
            }
    assert_equal(expected, result)
  end


end
