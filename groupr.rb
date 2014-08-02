#!/usr/bin/env ruby

$: << File.expand_path("../lib", __FILE__)
require "flickr/groupr"

CONFIG_FILE = File.expand_path("../.groupr", __FILE__)
VERBOSE = (ARGV.shift == "--verbose")
LAST_RUN_FILE = File.expand_path("../.last_run", __FILE__)

class GrouprApp
  include Flickr::Groupr

  attr_reader :config, :recent_time, :per_page

  def initialize
    if File.exists?(CONFIG_FILE) then
      @config = load_config()

    else
      @config = do_oauth()
      @config[:group] = select_group()
      @config[:album] = select_album()
      save_config(@config)
    end

    @per_page = 500
    @recent_time = Time.new-86400*7
    if File.exists?(LAST_RUN_FILE) then
      @recent_time = File.mtime(LAST_RUN_FILE)-(3600*3) # less a few hours of buffer time
    end
  end

  def run
    puts sprintf("Searching for new photos in album '%s' to add to '%s'", config["album"]["name"], config["group"]["name"]) if VERBOSE

    res = flickr.photosets.getPhotos(:photoset_id => config["album"]["id"],
                                        :extras => "date_upload", :per_page => @per_page)
    total_pages = res["pages"].to_i
    add_to_group(res["photo"])

    if total_pages > 1 then
      (2..total_pages).each do |page|
        puts sprintf("\nFetching page %s of %s", page, total_pages) if VERBOSE
        res = flickr.photosets.getPhotos(:photoset_id => config["album"]["id"],
                                         :extras => "date_upload",
                                         :per_page => @per_page, :page => page)
        add_to_group(res["photo"])
      end
    end

    FileUtils.touch(LAST_RUN_FILE)
    puts "Done!" if VERBOSE
  end

  def add_to_group(photos)
    photos.each do |photo|
      date = Time.at(photo["dateupload"].to_i)
      if date < @recent_time then
        # old photo
        puts sprintf("* skipping photo %s: %s < %s", photo["id"], date, @recent_time) if VERBOSE
        next
      end

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

end

GrouprApp.new.run
