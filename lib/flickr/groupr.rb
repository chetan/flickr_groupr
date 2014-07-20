
require "multi_json"
require "oj"
require "fileutils"
require "flickraw"

module Flickr
  module Groupr
    class << self

      def load_config()
        config = MultiJson.load(File.read(CONFIG_FILE))

        FlickRaw.api_key       = config["api_key"]
        FlickRaw.shared_secret = config["api_secret"]
        flickr.access_token    = config["access_token"]
        flickr.access_secret   = config["access_secret"]

        login = flickr.test.login
        puts "You are now authenticated as #{login.username}" if VERBOSE
      end

      def save_config(config)
        File.open(CONFIG_FILE, 'w'){ |f| f.write(MultiJson.dump(config)) }
      end

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
          :access_secret => flickr.access_secret
        }

        return config
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

    end
  end
end
