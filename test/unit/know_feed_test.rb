require File.dirname(__FILE__) + '/../test_helper'

class KnownFeedTest < Test::Unit::TestCase
  """Tests for the KnownFeed model class."""

  setup do
    Ohm.flush

    @topic = 'http://example.com/my-topic'
    @topic2 = 'http://example.com/my-topic2'
    @topic3 = 'http://example.com/my-topic3'
  end

  should "testCreateAndDelete" do
    known_feed = KnownFeed.create_with_key_name(:topic=>@topic)
    assert_equal(@topic, known_feed.topic)

    found_feed = KnownFeed.get_by_key_name(KnownFeed.create_key(@topic))
    assert_equal(found_feed.key_name, known_feed.key_name)
    assert_equal(found_feed.topic, known_feed.topic)

    found_feed.delete
    assert(KnownFeed.get_by_key_name(KnownFeed.create_key(@topic)).nil?)
  end

  should "testCheckExistsMissing" do
    assert_equal([], KnownFeed.check_exists([]))
    assert_equal([], KnownFeed.check_exists([@topic]))
    assert_equal([], KnownFeed.check_exists(
            [@topic, @topic2, @topic3]))
    assert_equal([], KnownFeed.check_exists(
            [@topic, @topic, @topic, @topic2, @topic2]))

  end

  should "testCheckExists" do
    KnownFeed.create_with_key_name(:topic=>@topic)
    KnownFeed.create_with_key_name(:topic=>@topic2)
    KnownFeed.create_with_key_name(:topic=>@topic3)
    assert_equal([@topic], KnownFeed.check_exists([@topic]))
    assert_equal([@topic2], KnownFeed.check_exists([@topic2]))
    assert_equal([@topic3], KnownFeed.check_exists([@topic3]))
    assert_equal(
            [@topic, @topic2, @topic3].sort,
            KnownFeed.check_exists([@topic, @topic2, @topic3]).sort)
    assert_equal(
            [@topic, @topic2].sort,
            KnownFeed.check_exists(
                    [@topic, @topic, @topic, @topic2, @topic2]).sort)

  end

  should "testCheckExistsSubset" do
    KnownFeed.create_with_key_name(:topic=>@topic)
    KnownFeed.create_with_key_name(:topic=>@topic3)
    assert_equal(
            [@topic, @topic3].sort,
            KnownFeed.check_exists([@topic, @topic2, @topic3]).sort)
    assert_equal(
            [@topic, @topic3].sort,
            KnownFeed.check_exists(
                    [@topic, @topic, @topic,
                     @topic2, @topic2,
                     @topic3, @topic3]).sort)
  end

  should "testRecord" do
    """Tests the method for recording a feed's identity."""
    KnownFeed.record(@topic)
    # todo...
  end

end
