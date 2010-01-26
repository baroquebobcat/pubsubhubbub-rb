require File.dirname(__FILE__) + '/../test_helper'

class FeedIdentifierTest < Test::Unit::TestCase

  def load_data(file_name)
    File.open(File.dirname(__FILE__) + '/../data/' + file_name).read
  end

  setup do
    Ohm.flush
  end

  """Tests for identifying Atom-formatted feeds."""

  should "testGood" do
    feed_id = FeedIdentifier.new.identify(load_data('parsing.xml'), 'atom')
    assertEquals('tag:diveintomark.org,2001-07-29:/', feed_id)
  end

  should "testNoFeedId" do
    feed_id = FeedIdentifier.new.identify(load_data('atom_no_id.xml'), 'atom')
    assertTrue(feed_id.nil?)
  end

  should "testIncorrectFormat" do
    feed_id = FeedIdentifier.new.identify(load_data('rss_rdf.xml'), 'atom')
    assertTrue(feed_id.nil?)
  end

  should "testWhitespace" do
#    feed_id = FeedIdentifier.new.identify(load_data('whitespace_id.xml'), 'atom')
#    assertEquals('my feed id here', feed_id)
  end

  should "testBadFormat" do
#    assertRaises(xml.sax.SAXParseException,
#                      FeedIdentifier.new.identify,
#                      load_data('bad_feed.xml'),
#                      'atom')
  end

  """Tests for identifying RSS-formatted feeds."""

  should "testGood091" do
    feed_id = FeedIdentifier.new.identify(load_data('sampleRss091.xml'), 'rss')
    assertEquals('http://writetheweb.com', feed_id)
  end

  should "testGood092" do
    feed_id = FeedIdentifier.new.identify(load_data('sampleRss092.xml'), 'rss')
    assertEquals(
            'http://www.scripting.com/blog/categories/gratefulDead.html',
            feed_id)
  end

  should "testGood20" do
    feed_id = FeedIdentifier.new.identify(load_data('rss2sample.xml'), 'rss')
    assertEquals('http://liftoff.msfc.nasa.gov/', feed_id)
  end

  should "testGoodRdf" do
    feed_id = FeedIdentifier.new.identify(load_data('rss_rdf.xml'), 'rss')
    assertEquals('http://writetheweb.com', feed_id)
  end

  should "testNoFeedId" do
    feed_id = FeedIdentifier.new.identify(load_data('rss_no_link.xml'), 'rss')
    assertTrue(feed_id.nil?)
  end

  should "testIncorrectFormat" do
    feed_id = FeedIdentifier.new.identify(load_data('parsing.xml'), 'rss')
    assertTrue(feed_id.nil?)
  end

  should "testBadFormat" do
#    assertRaises(xml.sax.SAXParseException,
#                      FeedIdentifier.new.identify,
#                      load_data('bad_feed.xml'),
#                      'rss')
  end

end
