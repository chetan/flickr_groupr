#!/usr/bin/env ruby

require "pony"
require "roadie"
require "nokogiri"
require "tilt"
require "tidy_ffi"

$: << File.expand_path("../lib", __FILE__)
require "flickr/groupr"

CONFIG_FILE = File.expand_path("../.emailr", __FILE__)
VERBOSE = (ARGV.shift == "--verbose")


class EmailrApp
  include Flickr::Groupr

  def initialize
    @cutoff = Time.new - 86400*7
  end

  def email_date
    @cutoff.strftime("%b %-d, %Y")
  end

  def send_email(photos, config)

    # create email body html
    data = {
      photos:  photos,
      title:   config["title"],
      subject: sprintf("%s %s", config["subject"], Time.new.strftime("%b %-d, %Y"))
    }
    tpl = Tilt::ERBTemplate.new("template/email.html.erb")
    html = tpl.render(self, data)

    doc = Roadie::Document.new(html)
    html = doc.transform

    doc = Nokogiri::HTML.parse(html)
    doc.xpath('//comment()').each do |comment|
      next if comment.text.strip =~ /^\[if/
      comment.replace("")
    end
    html = TidyFFI::Tidy.clean(doc.serialize)

    # send email
    options = {
      :from      => config["from"],
      :to        => config["to"],
      :subject   => data[:subject],
      :html_body => html,

    }
    if config["smtp"]["address"] && !config["smtp"]["address"].empty? then
      config["smtp"]["authentication"] = config["smtp"]["authentication"].to_sym
      options[:via] = :smtp
      smtp_opts = {}
      config["smtp"].each { |k,v| smtp_opts[k.to_sym] = v } # convert smtp option keys to symbols for pony
      options[:via_options] = smtp_opts
    else
      options[:via] = :sendmail
    end

    Pony.mail(options)
    puts "email sent"
  end

  def run
    if File.exists?(CONFIG_FILE) then
      config = load_config()

    else
      puts "running autoconfiguration"
      puts

      # init config w/ oauth details
      config = do_oauth()

      # prompt for addition details
      config["group"]   = select_group()
      config["subject"] = prompt("email subject")
      config["title"]   = prompt("email title")
      config["from"]    = prompt("email from address")
      config["to"]      = prompt("email to address")

      config["smtp"] = { :address => "", :port => 587, :enable_starttls_auto => true,
                        :user_name => "", :password => "", :authentication => :plain,
                        :domain => "localhost.localdomain" }
      save_config(config)
      puts "config defaults to /usr/bin/sendmail. edit .emailr to use an smtp server"
    end

    photos = flickr.groups.pools.getPhotos(
                :group_id => config["group"]["id"],
                :extras => "description,date_taken,url_n,owner_name",
                :per_page => 100)

    data = []
    photos.each do |photo|
      photo = Flickr::Groupr::Photo.new(photo.to_hash)
      if photo.upload_date < @cutoff then
        break # stop looking for photos
      end
      data << photo
    end

    send_email(data, config)
  end

end


EmailrApp.new.run
