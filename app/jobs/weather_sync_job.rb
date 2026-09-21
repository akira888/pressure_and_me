class WeatherSyncJob < ApplicationJob
  queue_as :weather

  DATA_KINDS = WeatherSample.data_kinds.keys.freeze
  RECENT_LOOKBACK = 24.hours
  INITIAL_PERIOD = 7.days

  def perform(now: Time.current)
    Location.find_each do |location|
      DATA_KINDS.each do |data_kind|
        sync_location(location, data_kind, now)
      end
    end
  end

  private

  def sync_location(location, data_kind, now)
    latest = location.weather_samples.public_send(data_kind).maximum(:observed_at)
    from = [ latest || now - INITIAL_PERIOD, now - RECENT_LOOKBACK ].min
    Weather::Importer.call(location: location, from: from, to: now, data_kind: data_kind)
  end
end
