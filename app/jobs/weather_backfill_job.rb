class WeatherBackfillJob < ApplicationJob
  queue_as :weather

  BACKFILL_PERIOD = 7.days
  DATA_KINDS = WeatherSample.data_kinds.keys.freeze

  def perform(now: Time.current)
    from = now - BACKFILL_PERIOD
    Location.find_each do |location|
      DATA_KINDS.each do |data_kind|
        Weather::Importer.call(location: location, from: from, to: now, data_kind: data_kind)
      end
    end
  end
end
