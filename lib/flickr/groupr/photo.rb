
require "time"

module Flickr
  module Groupr

    class Photo < ::Hash

      def initialize(hash)
        super()
        self.merge!(hash)
        self
      end

      def date
        Time.parse(self["datetaken"])
      end

      def upload_date
        Time.at(self["dateadded"].to_i)
      end

      def url
        sprintf("https://www.flickr.com/photos/%s/%s", self["owner"], self["id"])
      end

      def has_title?
        has?("title")
      end

      def has_description?
        has?("description")
      end

      def video?
        self["media"] == "video"
      end


      private

      def has?(key)
        self[key] && !self[key].strip.empty?
      end

    end

  end
end
