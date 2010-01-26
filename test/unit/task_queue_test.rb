require File.dirname(__FILE__) + '/../test_helper'

class TaskQueueTest < Test::Unit::TestCase

  setup do
    Ohm.flush
  end

  should "just work" do

    params = { :auto_reconfirm => true,
               :subscription_key_name => 'hash_51d2f23803e1024129ea1d8fd00e6a35e78f4bfa',
               :secret => 'hello',
               :next_state => 'verified',
               :verify_token => ''
    }

    assert_equal 0, Task.all.size

    now = Time.now
    first_task = Task.create(:url => '/work/pull_feeds', :eta => now, :params => {'topic'=> 'aTopic1'})
    second_task = Task.create(:url => '/work/pull_feeds', :eta => now, :params => params)
    third_task = Task.create(:url => '/work/pull_feeds', :eta => now, :params => params)

    assert_equal 3, Task.all.size

    TaskQueue.add('test-feed-pulls', first_task)
    TaskQueue.add('test-feed-pulls', second_task)

    assert_equal 2, TaskQueue.all('test-feed-pulls').size

    found_task = TaskQueue.next('test-feed-pulls')
    assert_equal first_task, found_task

    assert_equal 2, Task.all.size

    found_tasks = TaskQueue.all('test-feed-pulls')
    assert_equal [second_task], found_tasks

    found_tasks = TaskQueue.all('test-feed-pulls')
    assert_equal 1, found_tasks.size

    tasks = TaskQueue.any
    assert_equal second_task, tasks.first

    found_tasks = TaskQueue.all('test-feed-pulls')
    assert_equal 0, found_tasks.size

    assert_equal 1, Task.all.size
  end


#  should 'not allow duplicates' do
#
#    params = { :topic => 'http://gdata.youtube.com/feeds/base/videos/-/pillow?max-results=10&orderby=published' }
#
#    assert_equal 0, Task.all.size
#
#    now = Time.now
#    Task.create(:url => '/work/pull_feeds', :eta => now, :params => params)
#    assert_equal 1, Task.all.size
#
#    duplicate_task = Task.create(:url => '/work/pull_feeds', :eta => now, :params => params)
#    assert duplicate_task.errors.size > 0
#
#    assert_equal 1, Task.all.size
#  end
end