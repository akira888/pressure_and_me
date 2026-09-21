class WeatherSyncJob < ApplicationJob
  queue_as :weather

  DATA_KINDS = WeatherSample.data_kinds.keys.freeze
  RECENT_LOOKBACK = 24.hours

  def perform(now: Time.current)
    Location.find_each do |location|
      DATA_KINDS.each do |data_kind|
        sync_location(location, data_kind, now)
      end
    end
  end

  private

  def sync_location(location, data_kind, now)
    latest = location.weather_samples.where(data_kind: data_kind, observed_at: ..now).maximum(:observed_at)
    from = [ latest || location.weather_history_start, now.beginning_of_hour - RECENT_LOOKBACK ].min
    Weather::Importer.call(location: location, from: from, to: now, data_kind: data_kind)
  end
end
