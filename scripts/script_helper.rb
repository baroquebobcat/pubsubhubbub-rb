ROOT_DIR = File.expand_path(File.dirname(__FILE__) + "/../") unless defined? ROOT_DIR

require "rubygems"

require ROOT_DIR + "/vendor/dependencies/lib/dependencies"

require "monk/glue"
require "ohm"
require "haml"
require "sass"

require "spawn"
require "faker"

Dir[root_path("app/models/*.rb")].each do |file|
  require file
end

Dir[root_path("lib/*.rb")].each do |file|
  require file
end

Ohm.connect(settings(:redis))

