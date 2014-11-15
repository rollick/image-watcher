require "mongo"
require "exifr"
require "murmurhash3"
require 'mini_magick'


class ImageHandler
    def self.perform(path, root_path, events)
        if path.match(/\.(jpg|png|jpeg)$/i)
            include Mongo

            gallery = MongoClient.new("localhost", 27017).db("gallery")
            images = gallery.collection("images")

            # If the event was "MOVED_FROM" or path doesn't exist then delete 
            # the record. When files are edited then btsync will move the 
            # old file version to an archive folder rather than delete/add.
            if events.include? "MOVED_FROM" || !File.exist?(path)
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
                    relative_path = path.gsub(root_path, '')
                    thumb_path = "#{root_path}/~thumbnails/#{hash}.jpg"

                    # Generate thumbnail
                    image = MiniMagick::Image.open(path)
                    image.combine_options do |c|
                      c.thumbnail '200x200^'
                      c.gravity 'center'
                      c.extent '200x200'
                    end
                    image.write thumb_path

                    image = {
                        "relative_path" => relative_path,
                        "path" => path,
                        "hash" => hash,
                        "dateTaken" => date_taken
                    }

                    images.insert(image)
                else
                    p "Skipping existing image (#{path})..."
                end
            end
        else
          p "Skipping non-image..."
        end
    end
end