require "optparse"
require "mongo"
require "exifr"
require "murmurhash3"


options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: handler.rb [options]"

  opts.on("-a", "--args [ARGUMENTS]", "Filename and flag arguments from fswatch (| as separator)") do |a|
    options[:args] = a
  end
end.parse!

parts = options[:args].split("|")

unless parts.length > 2
    raise "Path and flag not provided!"
end

path = parts[0]
is_file = parts.include? "IsFile"

if is_file && path.match(/\.(jpg|png|jpeg)$/i)
    include Mongo

    gallery = MongoClient.new("localhost", 27017).db("gallery")
    images = gallery.collection("images")

    # If path doesn't exist then delete the record
    if !File.exist?(path)
        p "Deleting image (#{path})..."
        
        # TODO: How to remove the deleted photo without the hash?
        #       Image path isn't very reliable.
        images.remove({:path => path})
    else
        hash = MurmurHash3::V32.str_hash(File.read(path))
        
        # If image doesn't exist in db then insert
        if images.find({:hash => hash}).count() == 0
            p "Inserting image (#{path})..."

            info = EXIFR::JPEG.new(path)
            date_taken = info.date_time_digitized ? info.date_time_digitized : (info.date_time ? info.date_time : Time.now)

            image = {
                "path" => path,
                "hash" => hash,
                "dateTaken" => date_taken
            }

            images.insert(image)
        else
            p "Skipping existing image (#{path})..."
        end
    end
end