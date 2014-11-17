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

                    # relative path for use by website
                    relative_path = path.gsub(root_path, '')

                    # Resize image
                    image_sizes = [
                        {
                            "path" => "#{root_path}/~resized/#{hash}_thumb.jpg",
                            "extent" => "200x200",
                            "thumbnail" => "200x200^"
                        },
                        {
                            "path" => "#{root_path}/~resized/#{hash}_small.jpg",
                            "resize" => "640x640"
                        },
                        {
                            "path" => "#{root_path}/~resized/#{hash}_medium.jpg",
                            "resize" => "1024x1024"
                        },
                        {
                            "path" => "#{root_path}/~resized/#{hash}_large.jpg",
                            "resize" => "1280x1280"
                        },
                        {
                            "path" => "#{root_path}/~resized/#{hash}_xlarge.jpg",
                            "resize" => "1440x1440"
                        }
                    ]

                    # Generate resized images
                    image_sizes.each do |size|
                        image = MiniMagick::Image.open(path)
                        image.combine_options do |c|
                            if size["thumbnail"]
                                c.thumbnail size["thumbnail"] 
                                c.extent size["extent"]
                                c.gravity "center"
                            elsif size["resize"]
                                c.resize size["resize"]
                            end
                        end

                        image.write size["path"]
                    end

                    # Create image 
                    image = {
                        "relative_path" => relative_path,
                        "path" => path,
                        "hash" => hash,
                        "date_taken" => date_taken,
                        "exif" => {
                            "width" => info.width,
                            "height" => info.height,
                            "comment" => info.comment,
                            "f_number" => info.exif.f_number.to_s,
                            "shutter_speed_value" => info.shutter_speed_value.to_s,
                            "aperture_value" => info.aperture_value
                        }
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