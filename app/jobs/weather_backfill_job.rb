class WeatherBackfillJob < ApplicationJob
  queue_as :weather

  DATA_KINDS = WeatherSample.data_kinds.keys.freeze

  def perform(location_id: nil, now: Time.current)
    locations = location_id.nil? ? Location.all : Location.where(id: location_id)
    locations.find_each do |location|
      DATA_KINDS.each do |data_kind|
        from = location.weather_history_start
        from = [ from, now.in_time_zone.beginning_of_day - 92.days ].max if data_kind == "realtime"
        Weather::Importer.call(location: location, from: from, to: now, data_kind: data_kind)
      end
    end
  end
end
