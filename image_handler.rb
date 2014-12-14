require "mongo"
require "exifr"
require "murmurhash3"
require "mini_magick"
require "yaml"


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
                    p "Checking gallery details..."

                    # Check if the gallery has a config. Search up a maximum 
                    # of 3 directories to find the gallery.yml
                    dir_name = File.dirname(path)
                    n = 0

                    Dir.chdir(dir_name)
                    begin
                        unless found_config = Dir.entries('.').include?('gallery.yml')
                            Dir.chdir("..")
                        end
                        n += 1
                    end while n < 3 and !found_config

                    extra_info = {}
                    if found_config
                        config = YAML.load(File.open("./gallery.yml").read)

                        if config["name"]
                            name = config["name"]
                            slug = name.downcase.strip.gsub(' ', '-').gsub(/[^\w-]/, '')
                            
                            galleries = gallery.collection("galleries")
                            gallery = galleries.find_one({:_id => slug})
                            unless gallery
                                gallery = galleries.insert({
                                    :_id => slug, 
                                    :name => name, 
                                    :password => config["password"]
                                })
                            end

                            extra_info["gallery_id"] = gallery["_id"]
                        end
                    else
                        p "... No gallery config found."
                    end

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

                    # Create image record with standard data and 
                    # extra info (eg associated gallery)
                    images.insert(image.merge(extra_info))
                else
                    p "Skipping existing image (#{path})..."
                end
            end
        else
          p "Skipping non-image..."
        end
    end
end