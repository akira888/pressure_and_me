require "net/http"
require "json"
require "time"

module Clients
  class OpenMeteoClient
    class Error < StandardError; end
    class TransportError < Error; end
    class InvalidResponse < Error; end
    class HTTPError < Error
      attr_reader :status

      def initialize(status)
        @status = status
        super("Open-Meteo returned HTTP #{status}")
      end
    end

    SOURCES = {
      "realtime" => [ "https://api.open-meteo.com/v1/forecast", "jma_seamless" ],
      "confirmed" => [ "https://archive-api.open-meteo.com/v1/archive", "ecmwf_ifs" ]
    }.freeze
    FIELDS = {
      "temperature_2m" => :temperature,
      "relative_humidity_2m" => :humidity,
      "precipitation" => :precipitation,
      "pressure_msl" => :pressure_msl,
      "weather_code" => :weather_code
    }.freeze
    TIME_ZONE = "Asia/Tokyo"

    def initialize(http: Net::HTTP)
      @http = http
    end

    # from/to are instants; both endpoints are included. The API returns whole days.
    def fetch(latitude:, longitude:, from:, to:, data_kind:)
      endpoint, model = SOURCES.fetch(data_kind.to_s) { raise ArgumentError, "Unknown data_kind" }
      latitude = coordinate(latitude, -90..90)
      longitude = coordinate(longitude, -180..180)
      unless [ from, to ].all? { |time| time.is_a?(Time) || time.is_a?(ActiveSupport::TimeWithZone) } && from <= to
        raise ArgumentError, "from/to must be ordered times"
      end

      uri = URI(endpoint)
      uri.query = URI.encode_www_form(latitude: latitude, longitude: longitude,
        start_date: from.in_time_zone(TIME_ZONE).to_date.iso8601,
        end_date: to.in_time_zone(TIME_ZONE).to_date.iso8601,
        hourly: FIELDS.keys.join(","), models: model, timezone: TIME_ZONE,
        temperature_unit: "celsius", precipitation_unit: "mm", timeformat: "iso8601")
      parse_response(request(uri)).select { |row| row.fetch(:observed_at).between?(from, to) }
    end

    private

    def request(uri)
      response = @http.start(uri.host, uri.port, use_ssl: true,
        open_timeout: 5, read_timeout: 15, write_timeout: 5, max_retries: 0) do |connection|
        connection.request(Net::HTTP::Get.new(uri))
      end
      raise HTTPError, response.code.to_i unless response.code.to_i.between?(200, 299)
      response.body
    rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError => error
      raise TransportError, "Open-Meteo connection failed (#{error.class})"
    end

    def parse_response(body)
      payload = JSON.parse(body)
      unless payload.is_a?(Hash) && !payload["error"] && payload["utc_offset_seconds"] == 32_400
        raise InvalidResponse, "Expected a successful response in Asia/Tokyo"
      end
      hourly = payload["hourly"]
      unless hourly.is_a?(Hash) && hourly["time"].is_a?(Array) &&
          FIELDS.keys.all? { |field| hourly[field].is_a?(Array) && hourly[field].size == hourly["time"].size }
        raise InvalidResponse, "Hourly arrays are missing or have different lengths"
      end
      times = hourly.fetch("time").map { |value| parse_time(value) }
      unless times.each_cons(2).all? { |left, right| left < right }
        raise InvalidResponse, "Hourly times must be unique and increasing"
      end
      times.each_with_index.filter_map do |time, index|
        values = FIELDS.to_h do |source, target|
          [ target, measurement(hourly.fetch(source).fetch(index), target) ]
        end
        next if values.values.all?(&:nil?)
        values.merge(observed_at: time)
      end
    rescue JSON::ParserError => error
      raise InvalidResponse, "Invalid JSON (#{error.class})"
    end

    def parse_time(value)
      unless value.is_a?(String) && /\A\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):00\z/.match?(value)
        raise InvalidResponse, "Expected an ISO8601 hourly time"
      end
      Date.iso8601(value.first(10)) # Reject impossible dates instead of normalizing them.
      Time.iso8601("#{value}:00+09:00")
    rescue ArgumentError
      raise InvalidResponse, "Invalid calendar date"
    end

    def measurement(value, field)
      return if value.nil?
      unless value.is_a?(Numeric) && value.finite?
        raise InvalidResponse, "#{field} must be numeric or null"
      end
      if %i[humidity weather_code].include?(field)
        raise InvalidResponse, "#{field} must be integral" unless value == value.to_i
        value.to_i
      else
        value
      end
    end

    def coordinate(value, range)
      number = Float(value)
      raise ArgumentError, "Invalid coordinates" unless number.finite? && range.cover?(number)
      number
    rescue TypeError
      raise ArgumentError, "Invalid coordinates"
    end
  end
end
