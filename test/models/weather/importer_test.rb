require "test_helper"
require_relative "../../support/domain_records"
require_relative "../../support/open_meteo_http"

class WeatherImporterTest < ActiveSupport::TestCase
  include DomainRecords

  setup do
    @http = OpenMeteoHTTP.new
    @arguments = { location: domain_location, from: Time.utc(2026, 9, 13, 15),
      to: Time.utc(2026, 9, 13, 17), data_kind: :realtime,
      client: Clients::OpenMeteoClient.new(http: @http) }
  end

  test "persists hourly values for the supplied location and returns the imported count" do
    assert_difference "WeatherSample.count", 3 do
      assert_equal 3, Weather::Importer.call(**@arguments)
    end
    row = domain_location.weather_samples.order(:observed_at).first
    assert row.realtime?
    assert_equal @arguments[:from], row.observed_at
    assert_equal BigDecimal("1013.25"), row.pressure_msl
    assert_equal BigDecimal("25.1"), row.temperature
    assert_equal 60, row.humidity
    assert_equal BigDecimal("0"), row.precipitation
    assert_equal 1, row.weather_code
    assert row.created_at.present?
    assert row.updated_at.present?
  end

  test "reimport updates existing hours and preserves IDs and creation times" do
    Weather::Importer.call(**@arguments)
    first = WeatherSample.order(:observed_at).first
    previous_time = Time.zone.local(2026, 9, 14, 12)
    first.update_columns(created_at: previous_time, updated_at: previous_time)
    @http.change_payload { |payload| payload["hourly"]["pressure_msl"][0] = 1009.5 }
    assert_no_difference "WeatherSample.count" do
      assert_equal 3, Weather::Importer.call(**@arguments)
    end
    assert_equal BigDecimal("1009.5"), first.reload.pressure_msl
    assert_equal previous_time, first.created_at
    assert_operator first.updated_at, :>, previous_time
    updated_at = first.updated_at
    assert_no_difference "WeatherSample.count" do
      assert_equal 3, Weather::Importer.call(**@arguments)
    end
    assert_equal updated_at, first.reload.updated_at
  end

  test "confirmed import never changes realtime values" do
    Weather::Importer.call(**@arguments)
    before = WeatherSample.realtime.order(:id).map(&:attributes)
    @http.change_payload { |payload| payload["hourly"]["pressure_msl"][0] = 1015.5 }
    assert_difference "WeatherSample.confirmed.count", 3 do
      Weather::Importer.call(**@arguments, data_kind: "confirmed")
    end
    assert_equal before, WeatherSample.realtime.order(:id).map(&:attributes)
    assert_equal BigDecimal("1015.5"), WeatherSample.confirmed.order(:observed_at).first.pressure_msl
  end

  test "imports are isolated by location" do
    Weather::Importer.call(**@arguments)
    other = build_record(Location, user: User.create!, latitude: 34.5, longitude: 135.5).tap(&:save!)
    assert_difference "WeatherSample.count", 3 do
      Weather::Importer.call(**@arguments, location: other)
    end
    assert_equal 3, other.weather_samples.count
    assert_equal 3, domain_location.weather_samples.count
    query = URI.decode_www_form(@http.requests.last.uri.query).to_h
    assert_equal "34.5", query["latitude"]
    assert_equal "135.5", query["longitude"]
  end

  test "overlapping intervals only add missing hours" do
    Weather::Importer.call(**@arguments, to: @arguments[:from] + 1.hour)
    assert_difference "WeatherSample.count", 1 do
      Weather::Importer.call(**@arguments, from: @arguments[:from] + 1.hour)
    end
    assert_equal 3, WeatherSample.count
  end

  test "only returned hours are stored and partial missing values remain null" do
    @http.change_payload do |payload|
      payload["hourly"]["pressure_msl"][0] = nil
      payload["hourly"].except("time").each_value { |values| values[1] = nil }
    end
    assert_equal 2, Weather::Importer.call(**@arguments, data_kind: :confirmed)
    first = WeatherSample.order(:observed_at).first
    assert_nil first.pressure_msl
    assert_equal BigDecimal("25.1"), first.temperature
    assert_not WeatherSample.exists?(observed_at: @arguments[:from] + 1.hour)
  end

  test "unavailable reimport does not erase previously stored observations" do
    Weather::Importer.call(**@arguments)
    before = WeatherSample.order(:id).map(&:attributes)
    @http.change_payload { |payload| payload["hourly"].except("time").each_value { |values| values.map! { nil } } }
    assert_equal 0, Weather::Importer.call(**@arguments)
    assert_equal before, WeatherSample.order(:id).map(&:attributes)
  end

  test "empty available interval performs no writes" do
    @http.change_payload { |payload| payload["hourly"].each_value(&:clear) }
    assert_no_difference "WeatherSample.count" do
      assert_equal 0, Weather::Importer.call(**@arguments)
    end
  end

  test "malformed later row cannot partially update or insert earlier rows" do
    Weather::Importer.call(**@arguments, to: @arguments[:from])
    before = WeatherSample.order(:id).map(&:attributes)
    @http.change_payload do |payload|
      payload["hourly"]["pressure_msl"][0] = 999.0
      payload["hourly"]["temperature_2m"][2] = "bad data"
    end
    assert_raises(Clients::OpenMeteoClient::InvalidResponse) { Weather::Importer.call(**@arguments) }
    assert_equal before, WeatherSample.order(:id).map(&:attributes)
  end

  test "transport and API failures propagate without changing stored data" do
    Weather::Importer.call(**@arguments)
    before = WeatherSample.order(:id).map(&:attributes)
    @http.code = "429"
    assert_raises(Clients::OpenMeteoClient::HTTPError) { Weather::Importer.call(**@arguments) }
    @http.error = Net::ReadTimeout.new("timed out")
    assert_raises(Clients::OpenMeteoClient::TransportError) { Weather::Importer.call(**@arguments) }
    assert_equal before, WeatherSample.order(:id).map(&:attributes)
  end

  test "rejects unsaved locations and invalid requests without HTTP or database writes" do
    [ { location: Location.new }, { data_kind: :unknown }, { from: @arguments[:to] + 1.hour } ].each do |invalid|
      assert_no_difference "WeatherSample.count" do
        assert_raises(ArgumentError) { Weather::Importer.call(**@arguments, **invalid) }
      end
    end
    assert_empty @http.requests
  end
end
