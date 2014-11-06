require "optparse"
require "mongo"
require "exifr"


options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: handler.rb [options]"

  opts.on("-a", "--args [ARGUMENTS]", "Filename and flag arguments from fswatch") do |a|
    options[:args] = a
  end
end.parse!

match = options[:args].match(/(^.*?)\s(\d+)$/i)

unless match.length > 2
    raise "Path and flag not provided!"
end 

path = match[1]
flag = match[2]

# If flag is 558 then the file was created
if flag == "528" && path.match(/\.jpg$/i)
    p "Inserting new record..."
    include Mongo

    gallery = MongoClient.new("localhost", 27017).db("gallery")
    images = gallery.collection("images")

    image = {
        "path" => path
    }

    info = EXIFR::JPEG.new(path)

    image["dateTaken"] = (info.exif? && info.date_time) ? info.date_time : Time.now

    p "=> #{image}"
    images.insert(image)
end