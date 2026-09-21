class WeatherBackfillJob < ApplicationJob
  queue_as :weather

  DATA_KINDS = WeatherSample.data_kinds.keys.freeze

  def perform(location_id: nil, now: Time.current)
    locations = location_id.nil? ? Location.all : Location.where(id: location_id)
    locations.find_each do |location|
      DATA_KINDS.each do |data_kind|
        Weather::Importer.call(location: location, from: location.weather_history_start, to: now, data_kind: data_kind)
      end
    end
  end
end
