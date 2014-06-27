#!/usr/bin/env ruby

require "multi_json"
require "oj"
require "fileutils"
require "flickraw"

CONFIG_FILE = File.expand_path("../.groupr", __FILE__)
VERBOSE = (ARGV.shift == "--verbose")

def do_oauth

  key    = ENV["FLICKR_KEY"]
  secret = ENV["FLICKR_SECRET"]

  if !(key && secret) then
    warn "FLICKR_KEY and FLICKR_SECRET environment variables must be set on the first run"
    exit 1
  end

  FlickRaw.api_key       = key
  FlickRaw.shared_secret = secret

  token = flickr.get_request_token
  auth_url = flickr.get_authorize_url(token['oauth_token'], :perms => 'delete')

  puts "You must authorize this app to access your flickr account"
  puts "Open this url in your browser to complete the authication process:\n#{auth_url}"
  STDOUT.write "Authorization code (XXX-XXX-XXX): "
  verify = gets.strip

  begin
    flickr.get_access_token(token['oauth_token'], token['oauth_token_secret'], verify)
    login = flickr.test.login
    puts "You are now authenticated as #{login.username}."

  rescue FlickRaw::FailedResponse => e
    puts "Authentication failed: #{e.message}"
    exit 1
  end

  config = {
    :api_key       => key,
    :api_secret    => secret,
    :access_token  => flickr.access_token,
    :access_secret => flickr.access_secret,

    :group         => select_group(),
    :album         => select_album()
  }
  File.open(CONFIG_FILE, 'w'){ |f| f.write(MultiJson.dump(config)) }

end

def select_group
  groups = flickr.groups.pools.getGroups

  puts "You are a member of #{groups.size} groups. Please make a selection"
  groups.each_with_index do |g, i|
    i += 1
    i = i.to_s
    i = (" " * (3-i.size)) + i

    puts sprintf("%s. %s", i, g["name"])
  end
  puts
  STDOUT.write "Group number: "
  num = gets.strip.to_i - 1

  group = groups[num]
  puts "You selected: " + group["name"]

  return {
    :id   => group["id"],
    :nsid => group["nsid"],
    :name => group["name"]
  }
end

def select_album
  albums = flickr.photosets.getList

  puts "Please select an album"
  albums.each_with_index do |g, i|
    i += 1
    i = i.to_s
    i = (" " * (3-i.size)) + i

    puts sprintf("%s. %s", i, g["title"])
  end
  puts
  STDOUT.write "Album number: "
  num = gets.strip.to_i - 1

  album = albums[num]
  puts "You selected: " + album["title"]

  return {
    :id   => album["id"],
    :name => album["title"]
  }
end

if File.exists?(CONFIG_FILE) then
  config = MultiJson.load(File.read(CONFIG_FILE))

  FlickRaw.api_key       = config["api_key"]
  FlickRaw.shared_secret = config["api_secret"]
  flickr.access_token    = config["access_token"]
  flickr.access_secret   = config["access_secret"]

  login = flickr.test.login
  puts "You are now authenticated as #{login.username}" if VERBOSE

else
  do_oauth()
end

LAST_RUN_FILE = File.expand_path("../.last_run", __FILE__)
recent_time = Time.new-86400*7
per_page = 500
if File.exists?(LAST_RUN_FILE) then
  recent_time = File.mtime(LAST_RUN_FILE)
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
