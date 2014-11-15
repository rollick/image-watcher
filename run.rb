require "optparse"
require "qu-mongo"

require_relative "./image_handler"


options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: handler.rb [options]"

  opts.on("-p", "--path PATH", "Path to file and list of events (| separated)") do |p|
    options[:path] = p
  end

  opts.on("-r", "--root-path ROOT_PATH", "Root path for images") do |r|
    options[:root_path] = r
  end
end.parse!

parts = options[:path].split("|")
path = parts.shift
events = parts

# No trailing slash for root path
root_path = options[:root_path].gsub(/\/$/, '')

job = Qu.enqueue ImageHandler, path, root_path, events
puts "Enqueued job #{job.id}"
