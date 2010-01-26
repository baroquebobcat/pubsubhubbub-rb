require File.dirname(__FILE__) + '/../test_helper'

class FindFeedUpdatesTest < Test::Unit::TestCase

  setup do
    Ohm.flush

    @topic = 'http://example.com/my-topic-here'
    @header_footer = '<feed>this is my test header footer</feed>'
    @entries_map = {
            'id1'=> 'content1',
            'id2'=> 'content2',
            'id3'=> 'content3',
            }
    @content = 'the expected response data'

#    def my_filter(content, ignored_format):
#      self.assertEquals(self.content, content)
#      return self.header_footer, self.entries_map
#    self.my_filter = my_filter
#

  end

  def sha1_hash(value)
    FindFeedUpdates.new.sha1_hash(value)
  end

  def run_test
    """Runs a test."""
    FeedDiff.any_instance.expects(:filter).with(@content, Main::ATOM).returns([@header_footer, @entries_map])

    header_footer, entry_list, entry_payloads = FindFeedUpdates.new.find_feed_updates(
            @topic, Main::ATOM, @content)
    assertEquals(@header_footer, header_footer)
    return entry_list, entry_payloads
  end

  def get_entry(entry_id, entry_list)
    """Finds the entry with the given ID in the list of entries."""
    entry_list.each do |e|      
      return e if e.entry_id == entry_id
    end
  end

  should "testAllNewContent" do
    """Tests when al pulled feed content is new."""
    entry_list, entry_payloads = run_test()
    entry_id_set = entry_list.collect {|f| f.entry_id }.to_set
    assertEquals(@entries_map.keys.to_set, entry_id_set)
    assertEquals(@entries_map.values, entry_payloads)

  end

  should "testSomeExistingEntries" do
    """Tests when some entries are already known."""
    FeedEntryRecord.create_entry_for_topic(
            @topic, 'id1', sha1_hash('content1'))
    FeedEntryRecord.create_entry_for_topic(
            @topic, 'id2', sha1_hash('content2'))

    entry_list, entry_payloads = run_test()
    entry_id_set = entry_list.collect {|f| f.entry_id }.to_set
    assertEquals(['id3'].to_set, entry_id_set)
    assertEquals(['content3'], entry_payloads)
  end

  should "testPulledEntryNewer" do
    """Tests when an entry is already known but has been updated recently."""
    FeedEntryRecord.create_entry_for_topic(
            @topic, 'id1', sha1_hash('content1'))
    FeedEntryRecord.create_entry_for_topic(
            @topic, 'id2', sha1_hash('content2'))
    @entries_map['id1'] = 'newcontent1'

    entry_list, entry_payloads = run_test()
    entry_id_set = entry_list.collect {|f| f.entry_id }.to_set
    assertEquals(['id1', 'id3'].to_set, entry_id_set)

    # Verify the old entry would be overwritten.
    entry1 = get_entry('id1', entry_list)
    assertEquals(sha1_hash('newcontent1'), entry1.entry_content_hash)
    assertEquals(['content3', 'newcontent1'].sort, entry_payloads.sort)
  end

#  def testUnicodeContent(self):
#    """Tests when the content contains unicode characters."""
#    self.entries_map['id2'] = u'\u2019 asdf'
#    entry_list, entry_payloads = self.run_test()
#    entry_id_set = set(f.entry_id for f in entry_list)
#    self.assertEquals(set(self.entries_map.keys()), entry_id_set)
#
#  def testMultipleParallelBatches(self):
#    """Tests that retrieving FeedEntryRecords is done in multiple batches."""
#    old_get_feed_record = main.FeedEntryRecord.get_entries_for_topic
#    calls = [0]
#    @staticmethod
#    def fake_get_record(*args, **kwargs):
#      calls[0] += 1
#      return old_get_feed_record(*args, **kwargs)
#
#    old_lookups = main.MAX_FEED_ENTRY_RECORD_LOOKUPS
#    main.FeedEntryRecord.get_entries_for_topic = fake_get_record
#    main.MAX_FEED_ENTRY_RECORD_LOOKUPS = 1
#    try:
#      entry_list, entry_payloads = self.run_test()
#      entry_id_set = set(f.entry_id for f in entry_list)
#      self.assertEquals(set(self.entries_map.keys()), entry_id_set)
#      self.assertEquals(self.entries_map.values(), entry_payloads)
#      self.assertEquals(3, calls[0])
#    finally:
#      main.MAX_FEED_ENTRY_RECORD_LOOKUPS = old_lookups
#      main.FeedEntryRecord.get_entries_for_topic = old_get_feed_record


end
