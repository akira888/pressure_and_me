module Weather
  class Importer
    MEASUREMENTS = %i[pressure_msl temperature humidity precipitation weather_code].freeze

    # The caller chooses the period; fetching finishes before any database write.
    # Returns the number of available hourly samples in the requested interval.
    def self.call(location:, from:, to:, data_kind:, client: Clients::OpenMeteoClient.new)
      unless location.is_a?(Location) && location.persisted?
        raise ArgumentError, "A persisted location is required"
      end
      kind = WeatherSample.data_kinds.fetch(data_kind.to_s) { raise ArgumentError, "Unknown data_kind" }
      samples = client.fetch(latitude: location.latitude, longitude: location.longitude,
        from: from, to: to, data_kind: data_kind)
      return 0 if samples.empty?

      rows = samples.map do |sample|
        sample.slice(:observed_at, *MEASUREMENTS).merge(location_id: location.id, data_kind: kind)
      end
      WeatherSample.upsert_all(rows,
        unique_by: %i[location_id observed_at data_kind],
        update_only: MEASUREMENTS, record_timestamps: true, returning: false)
      rows.size
    end
  end
end
