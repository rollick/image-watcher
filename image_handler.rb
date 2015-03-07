require "mongo"
require "exifr"
require "murmurhash3"
require "mini_magick"
require "yaml"
require "qu-mongo"


class ImageHandler < Qu::Job
    def initialize(path, root_path, events)
        @path = path
        @root_path = root_path
        @events = events
    end

    def perform
        # Check if the gallery has a config. Search up a maximum 
        # of 3 directories to find the gallery.yml
        dir_name = File.dirname(@path)
        n = 0

        Dir.chdir(dir_name)
        begin
            if found_config = Dir.entries(".").include?("gallery.yml")
                gallery_config = File.join(Dir.pwd, "gallery.yml")
            else
                Dir.chdir("..")
            end
            n += 1
        end while n < 3 and !found_config 
        
        if @path.match(/gallery.yml$/i)
             _update_gallery_details(gallery_config)

        elsif @path.match(/\.(jpg|png|jpeg)$/i)
            gallery_db = Mongo::MongoClient.new("localhost", 27017).db("gallery")
            images = gallery_db.collection("images")

            # If the event was "MOVED_FROM" or @path doesn't exist then delete 
            # the record. When files are edited then btsync/syncthing will move the 
            # old file version to an archive folder rather than delete/add.
            p "Does #{@path} exist? #{File.exist?(@path)}"
            if !File.exist?(@path) || @events.include?("MOVED_FROM")                
                # TODO: How to remove the deleted photo without the hash?
                #       Image path isn't very reliable.
                images.remove({:path => @path})
            else
                hash = MurmurHash3::V32.str_hash(File.read(@path))
                
                # If image doesn't exist in db then insert
                if images.find({:hash => hash}).count() == 0
                    p "Checking gallery details..."

                    extra_info = {}
                    if found_config
                        extra_info["gallery_id"] = _update_gallery_details(gallery_config)
                    else
                        p "... No gallery config found."
                    end

                    p "Inserting image (#{@path})..."

                    info = EXIFR::JPEG.new(@path)
                    date_taken = info.date_time_digitized ? info.date_time_digitized : (info.date_time ? info.date_time : Time.now)

                    # relative @path for use by website
                    relative_path = @path.gsub(@root_path, '')

                    # Resize image
                    image_sizes = [
                        {
                            "path" => "#{@root_path}/~resized/#{hash}_thumb.jpg",
                            "extent" => "200x200",
                            "thumbnail" => "200x200^"
                        },
                        {
                            "path" => "#{@root_path}/~resized/#{hash}_small.jpg",
                            "resize" => "640x640"
                        },
                        {
                            "path" => "#{@root_path}/~resized/#{hash}_medium.jpg",
                            "resize" => "1024x1024"
                        },
                        {
                            "path" => "#{@root_path}/~resized/#{hash}_large.jpg",
                            "resize" => "1280x1280"
                        },
                        {
                            "path" => "#{@root_path}/~resized/#{hash}_xlarge.jpg",
                            "resize" => "1440x1440"
                        }
                    ]

                    # Generate resized images
                    image_sizes.each do |size|
                        image = MiniMagick::Image.open(@path)
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
                        "path" => @path,
                        "hash" => hash,
                        "date_taken" => date_taken,
                        "exif" => {
                            "width" => info.width,
                            "height" => info.height,
                            "comment" => info.comment,
                            "f_number" => info.exif ? info.exif.f_number.to_s : nil,
                            "shutter_speed_value" => info.shutter_speed_value.to_s,
                            "aperture_value" => info.aperture_value
                        }
                    }

                    # Create image record with standard data and 
                    # extra info (eg associated gallery)
                    images.insert(image.merge(extra_info))
                else
                    p "Skipping existing image (#{@path})..."
                end
            end
        else
          p "Skipping file..."
        end
    end

    private 

    def _update_gallery_details(gallery_config)
        config = YAML.load(File.open(gallery_config).read)

        if config["name"]
            name = config["name"]
            slug = name.downcase.strip.gsub(' ', '-').gsub(/[^\w-]/, '')

            gallery_db = Mongo::MongoClient.new("localhost", 27017).db("gallery")
            galleries = gallery_db.collection("galleries")
            gallery = galleries.find_one({:_id => slug})

            if gallery
                # Update the gallery security details as these can change
                # name / slug can't be changed.
                p "Updating gallery - #{name}"
                galleries.update({:_id => gallery["_id"]}, {
                    "$set" => {
                        :question => config["question"],
                        :answer => config["answer"]
                    }
                })
            else
                p "Creating gallery - #{name}"
                gallery = galleries.insert({
                    :_id => slug,
                    :name => name,
                    :question => config["question"],
                    :answer => config["answer"]
                })
            end

            return gallery["_id"]
        end

        return nil
    end
end