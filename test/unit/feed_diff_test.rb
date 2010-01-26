require File.dirname(__FILE__) + '/../test_helper'

class FeedDiffTest < Test::Unit::TestCase

  def load_data(file_name)
    File.open(File.dirname(__FILE__) + '/../feed_diff_testdata/' + file_name).read
  end

  setup do
    @format = nil
    @feed_open = nil
    @feed_close = nil
    @entry_open = nil
    @entry_close = nil
  end

  def verify_entries(expected_list, entries)
    found_entries = entries.sort
    assertEquals expected_list.size, found_entries.size
    expected_list.zip(found_entries).each do |expected_key, found|
      found_key, found_content = found
#      this is a nokogiri thing...
#      assertEquals(expected_key, found_key)
      assertTrue(found_content.include?(@entry_open))
      assertTrue(found_content.include?(@entry_close))
    end
  end

  def load_feed(path)
    data = load_data(path)
    header_footer, entries = FeedDiff.new.filter(data, @format)
    assertTrue header_footer.include? @feed_open
    assertTrue header_footer.include? @feed_close
    return header_footer, entries
  end

  class AtomFeedDiffTest < FeedDiffTest

    setup do
      @format = 'atom'
      @feed_open = '<feed'
      @feed_close = '</feed>'
      @entry_open = '<entry>'
      @entry_close = '</entry>'
    end

    should "testParsing" do
      """Tests parsing."""
      header_footer, entries = load_feed('parsing.xml')
      expected_list = [
              'tag:diveintomark.org,2008-06-29:/archives/20080629044756',
              'tag:diveintomark.org,2008-07-04:/archives/20080704050619',
              'tag:diveintomark.org,2008-07-06:/archives/20080706022239',
              'tag:diveintomark.org,2008-07-12:/archives/20080712042845',
              'tag:diveintomark.org,2008-07-13:/archives/20080713011654',
              'tag:diveintomark.org,2008-07-17:/archives/20080717044506',
              'tag:diveintomark.org,2008-07-23:/archives/20080723030709',
              'tag:diveintomark.org,2008-07-29:/archives/20080729021401',
              'tag:diveintomark.org,2008-08-05:/archives/20080805020410',
              'tag:diveintomark.org,2008-08-05:/archives/20080805155619',
              'tag:diveintomark.org,2008-08-06:/archives/20080806144009',
              'tag:diveintomark.org,2008-08-07:/archives/20080807025755',
              'tag:diveintomark.org,2008-08-07:/archives/20080807233337',
              'tag:diveintomark.org,2008-08-12:/archives/20080812160843',
              'tag:diveintomark.org,2008-08-14:/archives/20080814215936',
      ]

      verify_entries(expected_list, entries)
      # Verify whitespace cleanup.
      assertTrue(header_footer.include? '></feed>') # todo - replace with .ends_with
      # Verify preservation of '/>' closings.
      assertTrue(header_footer.include? "<link href=\"http://diveintomark.org/\" rel=\"alternate\" type=\"text/html\">")
    end

    should "testEntityEscaping" do
      """Tests when certain external entities show up in the feed.

     Example: '&amp;nbsp' will be converted to '&nbsp;' by the parser, but then
     the new output entity won't be resolved.
     """
      header_footer, entries = load_feed('entity_escaping.xml')

      entries.each_pair do |key, content|
        assertTrue(content.include? '&amp;nbsp;')
      end

    end

    should "testAttributeEscaping" do
#     """Tests when certain external entities show up in an XML attribute.
#
#     Example: gd:foo="&quot;blah&quot;" will be converted to
#     gd:foo=""blah"" by the parser, which is not valid XML when reconstructing
#     the result.
#     """
      header_footer, entries = load_feed('attribute_escaping.xml')
      assertTrue(header_footer.include? "foo:myattribute=\"&quot;'foobar'&quot;\"")
    end

    should "testInvalidFeed" do
      """Tests when the feed is not a valid Atom document."""
      data = load_data('bad_atom_feed.xml')
      begin
        FeedDiff.new.filter(data, 'atom')
      rescue StandardError => e
        assertTrue(e.message.include? 'Enclosing tag is not <feed></feed>')
        return
      end
      fail
    end

    should "testNoXmlHeader" do
      """Tests that feeds with no XML header are accepted."""
      data = load_data('no_xml_header.xml')
      header_footer, entries = FeedDiff.new.filter(data, 'atom')
      assertEquals(1, entries.size)
    end

    should "testMissingId" do
      """Tests when an Atom entry is missing its ID field."""
      data = load_data('missing_entry_id.xml')
      begin
        FeedDiff.new.filter(data, 'atom')
      rescue StandardError => e
        assertTrue(e.message.include? '<entry> element missing <id>')
        return
      end
      fail
    end

    should "testFailsOnRss" do
      """Tests that parsing an RSS feed as Atom will fail."""
      data = load_data('rss2sample.xml')
      begin
        FeedDiff.new.filter(data, 'atom')
      rescue StandardError => e
        assertTrue(e.message.eql? 'Enclosing tag is not <feed></feed>')
        return
      end
      fai
    end
  end

  class RssFeedDiffTest < FeedDiffTest

    setup do
      @format = 'rss'
      @feed_open = '<rss'
      @feed_close = '</rss>'
      @entry_open = '<item>'
      @entry_close = '</item>'
    end

    should "testParsingRss20" do
      """Tests parsing RSS 2.0."""
      header_footer, entries = load_feed('rss2sample.xml')

      expected_list = [
              'http://liftoff.msfc.nasa.gov/2003/05/20.html#item570',
              'http://liftoff.msfc.nasa.gov/2003/05/27.html#item571',
              'http://liftoff.msfc.nasa.gov/2003/05/30.html#item572',
              'http://liftoff.msfc.nasa.gov/2003/06/03.html#item573',
      ]
      verify_entries(expected_list, entries)
      # Verify whitespace cleanup.
      assertTrue(header_footer.include? '></channel></rss>')
      # Verify preservation of '/>' closings.
      assertTrue(header_footer.include? '<mycoolelement wooh="fun"></mycoolelement>')
    end

    should "testParsingRss091" do
      """Tests parsing RSS 0.91."""
      header_footer, entries = load_feed('sampleRss091.xml')
      expected_list = [
              'http://writetheweb.com/read.php?item=19',
              'http://writetheweb.com/read.php?item=20',
              'http://writetheweb.com/read.php?item=21',
              'http://writetheweb.com/read.php?item=22',
              'http://writetheweb.com/read.php?item=23',
              'http://writetheweb.com/read.php?item=24',
      ]
      verify_entries(expected_list, entries)
    end

    should "testParsingRss092" do
      """Tests parsing RSS 0.92 with enclosures and only descriptions."""
      header_footer, entries = load_feed('sampleRss092.xml')
      expected_list = [
              '&lt;a href="http://arts.ucsc.edu/GDead/AGDL/other1.html"&gt;The Other One&lt;/a&gt;, live instrumental, One From The Vault. Very rhythmic very spacy, you can listen to it many times, and enjoy something new every time.',
              '&lt;a href="http://www.cs.cmu.edu/~mleone/gdead/dead-lyrics/Franklin\'s_Tower.txt"&gt;Franklin\'s Tower&lt;/a&gt;, a live version from One From The Vault.',
              '&lt;a href="http://www.scripting.com/mp3s/youWinAgain.mp3"&gt;The news is out&lt;/a&gt;, all over town..&lt;p&gt;\nYou\'ve been seen, out runnin round. &lt;p&gt;\nThe lyrics are &lt;a href="http://www.cs.cmu.edu/~mleone/gdead/dead-lyrics/You_Win_Again.txt"&gt;here&lt;/a&gt;, short and sweet. &lt;p&gt;\n&lt;i&gt;You win again!&lt;/i&gt;',
              "It's been a few days since I added a song to the Grateful Dead channel. Now that there are all these new Radio users, many of whom are tuned into this channel (it's #16 on the hotlist of upstreaming Radio users, there's no way of knowing how many non-upstreaming users are subscribing, have to do something about this..). Anyway, tonight's song is a live version of Weather Report Suite from Dick's Picks Volume 7. It's wistful music. Of course a beautiful song, oft-quoted here on Scripting News. &lt;i&gt;A little change, the wind and rain.&lt;/i&gt;",
              'Kevin Drennan started a &lt;a href="http://deadend.editthispage.com/"&gt;Grateful Dead Weblog&lt;/a&gt;. Hey it\'s cool, he even has a &lt;a href="http://deadend.editthispage.com/directory/61"&gt;directory&lt;/a&gt;. &lt;i&gt;A Frontier 7 feature.&lt;/i&gt;',
              'Moshe Weitzman says Shakedown Street is what I\'m lookin for for tonight. I\'m listening right now. It\'s one of my favorites. "Don\'t tell me this town ain\'t got no heart." Too bright. I like the jazziness of Weather Report Suite. Dreamy and soft. How about The Other One? "Spanish lady come to me.."',
              'The HTML rendering almost &lt;a href="http://validator.w3.org/check/referer"&gt;validates&lt;/a&gt;. Close. Hey I wonder if anyone has ever published a style guide for ALT attributes on images? What are you supposed to say in the ALT attribute? I sure don\'t know. If you\'re blind send me an email if u cn rd ths.',
              'This is a test of a change I just made. Still diggin..',
      ]
      verify_entries(expected_list, entries)
    end

    should "testOnlyLink" do
      """Tests when an RSS item only has a link element."""
      header_footer, entries = load_feed('rss2_only_link.xml')
      expected_list = [
              'http://liftoff.msfc.nasa.gov/news/2003/news-VASIMR.asp',
              'http://liftoff.msfc.nasa.gov/news/2003/news-laundry.asp',
              'http://liftoff.msfc.nasa.gov/news/2003/news-starcity.asp',
      ]
      verify_entries(expected_list, entries)
    end

    should "testOnlyTitle" do
      """Tests when an RSS item only has a title element."""
      header_footer, entries = load_feed('rss2_only_title.xml')
      expected_list = [
              "Astronauts' Dirty Laundry",
              'Star City',
              'The Engine That Does More',
      ]
      verify_entries(expected_list, entries)
    end

    should "testFailsOnAtom" do
      """Tests that parsing an Atom feed as RSS will fail."""
      begin
        data = load_data('parsing.xml')
        FeedDiff.new.filter(data, 'rss')
      rescue StandardError => e
        assertTrue(e.message.include? 'Enclosing tag is not <rss></rss>')
        return
      end
      fail
    end

  end

  class RssRdfFeedDiffTest < FeedDiffTest

    setup do
      @format = 'rss'
      @feed_open = '<rdf:RDF'
      @feed_close = '</rdf:RDF>'
      @entry_open = '<item'
      @entry_close = '</item>'
    end

    should "testParsingRss10Rdf" do
      """Tests parsing RSS 1.0, which is actually an RDF document."""
      header_footer, entries = load_feed('rss_rdf.xml')
      expected_list = [
              'http://writetheweb.com/read.php?item=23',
              'http://writetheweb.com/read.php?item=24',
      ]
      verify_entries(expected_list, entries)
    end

  end

  class FilterTest < FeedDiffTest
    setup do
      @format = 'atom'
    end

    should "testEntities" do
      """Tests that external entities cause parsing to fail."""
      begin
        load_feed('xhtml_entities.xml')
        fail('Should have raised an exception')
      rescue StandardError => e
        assertFalse(e.message.eql? 'IOError')
      end
    end
  end

  class YoutubeTest < FeedDiffTest
    setup do
      @format = 'atom'
    end

    should "testEntities" do
      """Tests that external entities cause parsing to fail."""
      begin
        data = load_data('youtube_api.xml')
        header_footer, entries = FeedDiff.new.filter(data, @format)
        assert_equal 10, entries.keys.size
      rescue StandardError => e
        assertFalse(e.message.eql? 'IOError')
      end
    end
  end

end
