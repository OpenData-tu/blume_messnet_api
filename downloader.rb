#from https://github.com/dirkschumacher/blume_crawler

require 'mongoid'
require 'httparty'
require_relative 'models/page.rb'

def check_and_download(date)
    #TODO do we still need these next couple lines now that we've moved this method here?
    env = ENV['ENV'] == 'production' ? :production : :development
    #Mongo::Logger.logger.level = ::Logger::FATAL
    Mongoid.load!("./mongoid.yml", env)

    base_url = 'http://www.stadtentwicklung.berlin.de/umwelt/luftqualitaet/de/messnetz/tageswerte/download/%s.html'
    url_id = Date.parse(date).strftime('%Y%m%d')
    url_to_download = base_url % url_id
    # date_is_recent = Date.today - date < 5
    page_already_exists = Page.where(url: url_to_download).exists?

    response = HTTParty.get(url_to_download)
    body = response.body.to_s.encode('UTF-8', {:invalid => :replace, :undef => :replace, :replace => '?'})
    page = nil
    if page_already_exists
        page = Page.where(url: url_to_download).first
        page.update_attributes!(
          content: body,
          date_download: DateTime.now
        )
        puts 'Updated %s' % url_id
        return page
    else
        page = Page.create(
          content: body,
          url: url_to_download,
          date_download: DateTime.now
        )
        puts 'Inserted %s' % url_id
        return page
    end
    sleep(1)

    return -1
end
