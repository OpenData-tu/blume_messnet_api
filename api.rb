require 'sinatra'
require 'csv'
require 'mongoid'
require 'httparty'
require 'nokogiri'
require_relative 'models/page.rb'
require_relative './models/sensor.rb'
require_relative './models/sensor_data.rb'

configure do
  Mongoid.load!('./mongoid.yml')
end

NO_DATA_RESPONSE = "No data available."

def prepare_for_export(sensor_data)
    converted_data = sensor_data.asc(:date).map do |e|
        {
            sensor_id: e.sensor.nil? ? :null : e.sensor.sensor_id,
            date: e.date,
            partikelPM10Mittel: e.partikelPM10Mittel,
            partikelPM10Ueberschreitungen: e.partikelPM10Ueberschreitungen,
            russMittel: e.russMittel,
            russMax3h: e.russMax3h,
            stickstoffdioxidMittel: e.stickstoffdioxidMittel,
            stickstoffdioxidMax1h: e.stickstoffdioxidMax1h,
            benzolMittel: e.benzolMittel,
            benzolMax1h: e.benzolMax1h,
            kohlenmonoxidMittel: e.kohlenmonoxidMittel,
            kohlenmonoxidMax8hMittel: e.kohlenmonoxidMax8hMittel,
            ozonMax1h: e.ozonMax1h,
            ozonMax8hMittel: e.ozonMax8hMittel,
            schwefeldioxidMittel: e.schwefeldioxidMittel,
            schwefeldioxidMax1h: e.schwefeldioxidMax1h
        }
    end
    converted_data
end

def convert_to_json(sensor_data)
    data = prepare_for_export(sensor_data)
    data = NO_DATA_RESPONSE if data.nil? || data.empty?
    data.to_json
end

def convert_to_csv(sensor_data)
    data = prepare_for_export sensor_data
    return NO_DATA_RESPONSE if data.nil? || data.empty?
    csv_string = CSV.generate do |csv|
        csv << data.first.keys
        data.each do |hash|
            csv << hash.values
        end
    end
    csv_string
end

def sensor_data_for_station(station)
  sensor = Sensor.for_sensor(station)
  sensor.sensor_data
end

def sensor_data_for_station_by_year(station, year)
  sensor_data_for_station(station).for_year(year)
end

def check_and_download(date)
    # we will crawl from 2008-01-01 until today
    env = ENV['ENV'] == 'production' ? :production : :development
    # Mongo::Logger.logger.level = ::Logger::FATAL
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

def extract_number(cell_text)
    cell_text.to_f if cell_text.match(/[-+]?([0-9]*\.[0-9]+|[0-9]+)/)
end

def parse_document(page)
    date_string = page.url.match(/[0-9]+/)[0]
    date = Date.new(date_string[0, 4].to_i, date_string[4, 2].to_i, date_string[6, 2].to_i)
    html_doc = Nokogiri::HTML page.content
    rows = html_doc.css('table.datenhellgrauklein tr')
    rows.each do |row|
        cells = row.css('td').to_a
        if cells.length == 15
            sensor_id = cells[0].inner_html.slice(0,3)
            next unless sensor_id.match(/[0-9]{3}/)
            sensor = Sensor.new(sensor_id: sensor_id)
            sensor.upsert
            sensor = Sensor.where(sensor_id: sensor_id).first
            unless SensorData.where(date: date).where(sensor_id: sensor._id).exists?
                sensor_data = SensorData.new(
                    date: date,
                    sensor_id: sensor._id,
                    partikelPM10Mittel: extract_number(cells[1].inner_html),
                    partikelPM10Ueberschreitungen: extract_number(cells[2].inner_html),
                    russMittel: extract_number(cells[3].inner_html),
                    russMax3h: extract_number(cells[4].inner_html),
                    stickstoffdioxidMittel: extract_number(cells[5].inner_html),
                    stickstoffdioxidMax1h: extract_number(cells[6].inner_html),
                    benzolMittel: extract_number(cells[7].inner_html),
                    benzolMax1h: extract_number(cells[8].inner_html),
                    kohlenmonoxidMittel: extract_number(cells[9].inner_html),
                    kohlenmonoxidMax8hMittel: extract_number(cells[10].inner_html),
                    ozonMax1h: extract_number(cells[11].inner_html),
                    ozonMax8hMittel: extract_number(cells[12].inner_html),
                    schwefeldioxidMittel: extract_number(cells[13].inner_html),
                    schwefeldioxidMax1h: extract_number(cells[14].inner_html)
                )
                sensor_data.upsert
            end
        end
    end
end
#puts SensorData.where(date: Date.new(2014, 5, 13)).where(sensor_id: "53a1ed3ba0cb4c3f81000001" ).exists?
#puts SensorData.all.to_a.first.date
def analyse()
    Page.all.map { |e| parse_document(e) }
    puts 'finished analyzing'
end


get '/api/v1/stations' do
  content_type :json
  Sensor.all.map { |e| {sensor_id: e.sensor_id} }.to_json
end

get '/api/v1/stations/:station' do
  content_type :json
  convert_to_json sensor_data_for_station(params[:station])
end

get '/api/v1/stations/:station/csv' do
  content_type :csv
  convert_to_csv sensor_data_for_station(params[:station])
end

get '/api/v1/stations/:station/sensordata/:year' do
  content_type :json
  convert_to_json sensor_data_for_station_by_year(params[:station], params[:year].to_i)
end

get '/api/v1/stations/:station/sensordata/:year/csv' do
  content_type :csv
  convert_to_csv sensor_data_for_station_by_year(params[:station], params[:year].to_i)
end

get '/api/v1/sensordata/yearly/:year' do
  content_type :json
  convert_to_json SensorData.for_year(params[:year].to_i)
end

get '/api/v1/sensordata/:date' do
  content_type :json
  convert_to_json SensorData.for_date(params[:date])
end

get '/api/v1/download/:date' do
  page = check_and_download(params[:date])
  puts 'page craled, will analyze'
  analyse()
end

get '/api/v1/sensordata/:year/csv' do
  content_type :csv
  convert_to_csv SensorData.for_year(params[:year].to_i)
end

get '/api/v1/recent' do
  content_type :json
  convert_to_json SensorData.recent
end

get '/api/v1/recent/csv' do
  content_type :csv
  convert_to_csv SensorData.recent
end

