#!/usr/bin/env ruby

$: << File.expand_path("../lib", __FILE__)
require "flickr/groupr"

CONFIG_FILE = File.expand_path("../.groupr", __FILE__)
VERBOSE = (ARGV.shift == "--verbose")
LAST_RUN_FILE = File.expand_path("../.last_run", __FILE__)

class GrouprApp
  include Flickr::Groupr

  def run

    if File.exists?(CONFIG_FILE) then
      config = load_config()

    else
      config = do_oauth()
      config[:group] = select_group()
      config[:album] = select_album()
      save_config()
    end

    recent_time = Time.new-86400*7
    per_page = 500
    if File.exists?(LAST_RUN_FILE) then
      recent_time = File.mtime(LAST_RUN_FILE)-(3600*3) # less a few hours of buffer time
      per_page = 50
    end

    puts sprintf("Searching for new photos in album '%s' to add to '%s'", config["album"]["name"], config["group"]["name"]) if VERBOSE

    photos = flickr.photosets.getPhotos(:photoset_id => config["album"]["id"],
                                        :extras => "date_upload", :per_page => per_page)

    photos = photos["photo"]
    photos.each do |photo|
      date = Time.at(photo["dateupload"].to_i)
      if date >= recent_time then
        # new photo! add to group
        puts sprintf("* adding new photo '%s' (%s) to group", photo["title"], photo["id"]) if VERBOSE
        begin
          flickr.groups.pools.add(:photo_id => photo["id"], :group_id => config["group"]["id"])
        rescue FlickRaw::FailedResponse => ex
          if ex.message =~ /already/ then
            puts sprintf("  (oops, photo was already in the group! moving on)") if VERBOSE
          else
            warn "  ERROR! #{ex.message}"
            if !VERBOSE then
              warn sprintf("         while adding photo '%s' (%s) to group '%s'", photo["title"], photo["id"], config["group"]["name"])
            end
          end
        end
      end
    end

    FileUtils.touch(LAST_RUN_FILE)
    puts "Done!" if VERBOSE

  end
end

GrouprApp.new.run
