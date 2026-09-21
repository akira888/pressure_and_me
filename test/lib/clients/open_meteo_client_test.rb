require "test_helper"
require_relative "../../support/open_meteo_http"

class OpenMeteoClientTest < ActiveSupport::TestCase
  setup do
    @http = OpenMeteoHTTP.new
    @client = Clients::OpenMeteoClient.new(http: @http)
    @arguments = { latitude: BigDecimal("35.681236"), longitude: BigDecimal("139.767125"),
      from: Time.utc(2026, 9, 13, 15), to: Time.utc(2026, 9, 13, 17), data_kind: :realtime }
  end

  test "requests JMA forecast with explicit dates units and Tokyo timezone" do
    @client.fetch(**@arguments)
    assert_equal "api.open-meteo.com", @http.host
    assert_equal 443, @http.port
    request = @http.requests.sole
    assert_equal "GET", request.method
    assert_equal "/v1/forecast", request.uri.path
    query = URI.decode_www_form(request.uri.query).to_h
    assert_equal "35.681236", query.fetch("latitude")
    assert_equal "139.767125", query.fetch("longitude")
    assert_equal "jma_seamless", query.fetch("models")
    assert_equal "Asia/Tokyo", query.fetch("timezone")
    assert_equal "2026-09-14", query.fetch("start_date")
    assert_equal "2026-09-14", query.fetch("end_date")
    assert_equal "celsius", query.fetch("temperature_unit")
    assert_equal "mm", query.fetch("precipitation_unit")
    assert_equal "iso8601", query.fetch("timeformat")
    assert_equal %w[temperature_2m relative_humidity_2m precipitation pressure_msl weather_code].sort,
      query.fetch("hourly").split(",").sort
    assert_equal true, @http.options.fetch(:use_ssl)
    %i[open_timeout read_timeout write_timeout].each { |key| assert_operator @http.options.fetch(key), :>, 0 }
    assert_equal 0, @http.options.fetch(:max_retries)
  end

  test "requests IFS archive for confirmed data including the requested end date" do
    @client.fetch(**@arguments, data_kind: "confirmed")
    assert_equal "archive-api.open-meteo.com", @http.host
    request = @http.requests.sole
    assert_equal "/v1/archive", request.uri.path
    query = URI.decode_www_form(request.uri.query).to_h
    assert_equal "ecmwf_ifs", query.fetch("models")
    assert_equal "2026-09-14", query.fetch("end_date")
  end

  test "maps hourly values and parses local times independently of application timezone" do
    rows = Time.use_zone("UTC") { @client.fetch(**@arguments) }
    assert_equal 3, rows.size
    assert_equal({ observed_at: Time.utc(2026, 9, 13, 15), temperature: 25.1, humidity: 60,
      precipitation: 0.0, pressure_msl: 1013.25, weather_code: 1 }, rows.first)
  end

  test "returns only hours within the inclusive requested interval" do
    rows = @client.fetch(**@arguments, from: @arguments[:from] + 1.second, to: @arguments[:to] - 1.second)
    assert_equal [ Time.utc(2026, 9, 13, 16) ], rows.pluck(:observed_at)
    assert_equal 1, @client.fetch(**@arguments, to: @arguments[:from]).size
  end

  test "rejects invalid kind coordinates and ranges before HTTP" do
    [ { data_kind: :unknown }, { data_kind: nil }, { latitude: 91 }, { longitude: -181 },
      { latitude: "abc" }, { longitude: Float::INFINITY }, { from: nil },
      { from: Date.new(2026, 9, 14) }, { to: @arguments[:from] - 1.second } ].each do |invalid|
      assert_raises(ArgumentError) { @client.fetch(**@arguments, **invalid) }
    end
    assert_empty @http.requests
  end

  test "keeps partial null values but omits hours with no available values" do
    @http.change_payload do |payload|
      payload["hourly"]["pressure_msl"][0] = nil
      payload["hourly"].except("time").each_value { |values| values[1] = nil }
    end
    rows = @client.fetch(**@arguments)
    assert_equal 2, rows.size
    assert_nil rows.first.fetch(:pressure_msl)
    assert_equal 25.1, rows.first.fetch(:temperature)
  end

  test "accepts an empty available period without inventing observations" do
    @http.change_payload { |payload| payload["hourly"].each_value(&:clear) }
    assert_empty @client.fetch(**@arguments)
  end

  test "normalizes integral numeric humidity and weather codes" do
    @http.change_payload do |payload|
      payload["hourly"]["relative_humidity_2m"][0] = 60.0
      payload["hourly"]["weather_code"][0] = 1.0
    end
    row = @client.fetch(**@arguments).first
    assert_instance_of Integer, row.fetch(:humidity)
    assert_instance_of Integer, row.fetch(:weather_code)
  end

  test "reports non success HTTP statuses without parsing or following redirects" do
    %w[301 400 429 500].each do |status|
      @http.code = status
      @http.body = "upstream error"
      error = assert_raises(Clients::OpenMeteoClient::HTTPError) { @client.fetch(**@arguments) }
      assert_equal status.to_i, error.status
    end
    assert_equal 4, @http.requests.size
  end

  test "wraps transport failures without retrying" do
    [ Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, SocketError,
      EOFError, Errno::ECONNRESET, OpenSSL::SSL::SSLError ].each do |error_class|
      @http.error = error_class.new("connection failed")
      error = assert_raises(Clients::OpenMeteoClient::TransportError) { @client.fetch(**@arguments) }
      assert_instance_of error_class, error.cause
    end
    assert_equal 7, @http.requests.size
  end

  test "rejects invalid JSON and invalid top level payloads" do
    [ "not json", "null", "[]", "{}", '{"error":true,"reason":"invalid request"}' ].each do |body|
      @http.body = body
      assert_raises(Clients::OpenMeteoClient::InvalidResponse) { @client.fetch(**@arguments) }
    end
  end

  test "rejects missing fields malformed arrays and inconsistent timezone" do
    mutations = [
      ->(payload) { payload.delete("hourly") },
      ->(payload) { payload["hourly"] = nil },
      ->(payload) { payload["hourly"].delete("pressure_msl") },
      ->(payload) { payload["hourly"]["temperature_2m"] = "25" },
      ->(payload) { payload["hourly"]["weather_code"].pop },
      ->(payload) { payload["hourly"]["time"] = nil },
      ->(payload) { payload["utc_offset_seconds"] = 0 }
    ]
    original = @http.body
    mutations.each do |mutate|
      @http.body = original
      @http.change_payload(&mutate)
      assert_raises(Clients::OpenMeteoClient::InvalidResponse) { @client.fetch(**@arguments) }
    end
  end

  test "rejects bad timestamps duplicate hours and unordered hours" do
    original = @http.body
    [ nil, "not a date", "2026-02-30T00:00", "2026-09-14T24:00", "2026-09-14T00:30",
      "2026-09-14T01:00", "2026-09-14T03:00" ].each do |time|
      @http.body = original
      @http.change_payload { |payload| payload["hourly"]["time"][0] = time }
      assert_raises(Clients::OpenMeteoClient::InvalidResponse) { @client.fetch(**@arguments) }
    end
  end

  test "rejects malformed measurement types instead of coercing to zero" do
    original = @http.body
    [ [ "pressure_msl", "1013" ], [ "temperature_2m", true ], [ "precipitation", [] ],
      [ "relative_humidity_2m", 60.5 ], [ "weather_code", 1.5 ] ].each do |field, value|
      @http.body = original
      @http.change_payload { |payload| payload["hourly"][field][0] = value }
      assert_raises(Clients::OpenMeteoClient::InvalidResponse) { @client.fetch(**@arguments) }
    end
  end
end
