require 'sinatra'
require 'csv'
require 'mongoid'
require 'httparty'
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
    url_id = date.strftime('%Y%m%d')
    url_to_download = base_url % url_id
    date_is_recent = Date.today - date < 5
    page_already_exists = Page.where(url: url_to_download).exists?
    unless page_already_exists && !date_is_recent
        response = HTTParty.get(url_to_download)
        body = response.body.to_s.encode('UTF-8', {:invalid => :replace, :undef => :replace, :replace => '?'})
        if page_already_exists
            page = Page.where(url: url_to_download).first
            page.update_attributes!(
              content: body,
              date_download: DateTime.now
            )
            puts 'Updated %s' % url_id
        else
            Page.create(
              content: body,
              url: url_to_download,
              date_download: DateTime.now
            )
            puts 'Inserted %s' % url_id
        end
        sleep(1)
    end
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

get '/api/v1/sensordata/:year' do
  content_type :json
  convert_to_json SensorData.for_year(params[:year].to_i)
end

get '/api/v1/download/:date' do
  check_and_download(params[:year])
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

