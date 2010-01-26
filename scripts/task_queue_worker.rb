#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/script_helper'

require 'httpclient'

class TaskQueueRunner
  def run
    current_queue_size = Task.all.size
    logger.info("Working - current_queue_size=#{current_queue_size}")

    while current_queue_size > 0
      begin
        TaskQueue.any.each do |task|
          uri = URI("http://localhost:4567")
          uri.path = task.url
          http = HTTPClient.new unless http

          logger.debug("Sending work=#{task.url}, params=#{task.params}")

          response = http.post(uri, task.params)

          logger.info("Sent work=#{task.url}, params=#{task.params}")

          if response.code != 200
            logger.warn("Task failed #{response.code}. Added task back to queue #{task.queue_name}")
            task = Task.create(:url => task.url, :eta => Time.now, :params => task.params)
            TaskQueue.add(task.queue_name, task)
          else
            logger.debug("Successfully sent task to #{uri.to_s}")
          end
        end
        logger.debug("Sleeping, tasks remaining=#{Task.all.size}")
        sleep(0.5)
      rescue StandardError => e
        logger.error("Exiting, unable to complete work #{e}")
        exit(42)
      end
    end

  end
end
TaskQueueRunner.new.run