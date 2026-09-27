require "test_helper"
require_relative "../support/domain_records"
require_relative "../support/open_meteo_http"

class WeatherJobsTest < ActiveSupport::TestCase
  include DomainRecords
  include ActiveJob::TestHelper

  setup do
    @now = Time.zone.local(2026, 9, 21, 12)
    travel_to @now
    @calls = []
    calls = @calls
    @importer = ->(**arguments) { calls << arguments; arguments }
  end

  test "backfill imports the initial 24 hours for both series at every location" do
    first = domain_location
    second = build_record(Location, user: User.create!, latitude: "34.693738", longitude: "135.502165").tap(&:save!)

    with_importer_stub do
      WeatherBackfillJob.perform_now(now: @now)
    end

    assert_equal 4, @calls.size
    assert_equal [ first, first, second, second ], @calls.map { |call| call.fetch(:location) }
    assert_equal %w[realtime confirmed realtime confirmed], @calls.map { |call| call.fetch(:data_kind) }
    @calls.each do |call|
      assert_equal @now - 24.hours, call.fetch(:from)
      assert_equal @now, call.fetch(:to)
    end
  end

  test "backfill is safe when there are no locations" do
    with_importer_stub { WeatherBackfillJob.perform_now(now: @now) }
    assert_empty @calls
  end

  test "sync uses the latest sample as the lower bound and checks the recent gap" do
    location = domain_location
    WeatherSample.create!(location: location, observed_at: @now - 3.hours, data_kind: :realtime)
    WeatherSample.create!(location: location, observed_at: @now - 26.hours, data_kind: :confirmed)

    with_importer_stub do
      WeatherSyncJob.perform_now(now: @now)
    end

    assert_equal 2, @calls.size
    realtime = @calls.find { |call| call.fetch(:data_kind) == "realtime" }
    confirmed = @calls.find { |call| call.fetch(:data_kind) == "confirmed" }
    assert_equal @now - 24.hours, realtime.fetch(:from)
    assert_equal @now - 26.hours, confirmed.fetch(:from)
    assert_equal @now, realtime.fetch(:to)
    assert_equal @now, confirmed.fetch(:to)
  end

  test "sync backfills the initial 24 hours for a series with no samples" do
    location = domain_location
    WeatherSample.create!(location: location, observed_at: @now - 2.hours, data_kind: :realtime)

    with_importer_stub do
      WeatherSyncJob.perform_now(now: @now)
    end

    confirmed = @calls.find { |call| call.fetch(:data_kind) == "confirmed" }
    assert_equal @now - 24.hours, confirmed.fetch(:from)
    assert_equal 2, @calls.size
    assert_equal [ location ], @calls.map { |call| call.fetch(:location) }.uniq
  end

  test "jobs are enqueued on the weather queue" do
    assert_equal "weather", WeatherBackfillJob.queue_name
    assert_equal "weather", WeatherSyncJob.queue_name
  end

  test "jobs inherit the application job retry policy" do
    [ WeatherBackfillJob, WeatherSyncJob ].each do |job_class|
      assert job_class < ApplicationJob
    end
  end

  test "jobs can be enqueued without running in the caller" do
    assert_enqueued_with(job: WeatherBackfillJob, queue: "weather") { WeatherBackfillJob.perform_later }
    assert_enqueued_with(job: WeatherSyncJob, queue: "weather") { WeatherSyncJob.perform_later }
  end

  test "registration backfill targets only the supplied location" do
    location = domain_location
    build_record(Location, user: User.create!).save!
    with_importer_stub { WeatherBackfillJob.perform_now(location_id: location.id, now: @now) }
    assert_equal 2, @calls.size
    assert_equal [ location ], @calls.pluck(:location).uniq
  end

  test "deleted location does not turn a queued backfill into an all location import" do
    location = domain_location
    id = location.id
    location.destroy!
    build_record(Location, user: User.create!).save!
    with_importer_stub { WeatherBackfillJob.perform_now(location_id: id, now: @now) }
    assert_empty @calls
  end

  test "initial period includes the hour needed for a 24 hour pressure difference" do
    travel_to @now + 37.minutes do
      location = domain_location
      with_importer_stub { WeatherBackfillJob.perform_now(location_id: location.id) }
      @calls.each do |call|
        assert_equal @now - 24.hours, call.fetch(:from)
        assert_equal @now + 37.minutes, call.fetch(:to)
      end
    end
  end

  test "backfill reaches before the oldest condition log for historical analysis" do
    location = domain_location
    oldest = @now - 5.days - 37.minutes
    location.user.condition_logs.create!(headache: 5, nausea: 5, fatigue: 5, appetite: 5, clarity: 5,
      recorded_at: oldest)

    with_importer_stub { WeatherBackfillJob.perform_now(location_id: location.id, now: @now) }

    expected_start = oldest.beginning_of_hour - 24.hours
    assert_equal expected_start, @calls.first.fetch(:from)
    assert_equal expected_start, location.weather_history_start
  end

  test "delayed first jobs retain the period before registration" do
    location = domain_location
    travel_to @now + 3.days do
      with_importer_stub do
        WeatherBackfillJob.perform_now(location_id: location.id)
        WeatherSyncJob.perform_now
      end
      assert_equal 4, @calls.size
      @calls.each do |call|
        assert_equal @now - 24.hours, call.fetch(:from)
        assert_equal Time.current, call.fetch(:to)
      end
    end
  end

  test "restart catches up each series without limiting the outage to 24 hours" do
    location = domain_location
    WeatherSample.create!(location: location, observed_at: @now - 4.days, data_kind: :realtime)
    WeatherSample.create!(location: location, observed_at: @now - 2.days, data_kind: :confirmed)
    WeatherSample.create!(location: location, observed_at: @now + 1.day, data_kind: :realtime)
    with_importer_stub { WeatherSyncJob.perform_now(now: @now) }
    assert_equal @now - 4.days, @calls.find { |call| call[:data_kind] == "realtime" }.fetch(:from)
    assert_equal @now - 2.days, @calls.find { |call| call[:data_kind] == "confirmed" }.fetch(:from)
  end

  test "hourly sync includes the complete 24 hour analysis window" do
    location = domain_location
    WeatherSample.create!(location: location, observed_at: @now, data_kind: :realtime)
    with_importer_stub { WeatherSyncJob.perform_now(now: @now + 37.minutes) }
    assert_equal @now - 24.hours, @calls.find { |call| call[:data_kind] == "realtime" }.fetch(:from)
  end

  test "backfill and repeated sync repair a gap without duplicating either series" do
    original_importer = Weather::Importer.method(:call)
    client = Clients::OpenMeteoClient.new(http: OpenMeteoHTTP.new)
    @importer = ->(**arguments) { original_importer.call(**arguments, client: client) }

    travel_to Time.zone.local(2026, 9, 14, 12) do
      location = domain_location
      with_importer_stub do
        WeatherBackfillJob.perform_now(location_id: location.id)
        assert_equal 6, location.weather_samples.count
        confirmed_before = location.weather_samples.confirmed.order(:id).map(&:attributes)
        missing_hour = location.weather_samples.realtime.order(:observed_at).second.observed_at
        location.weather_samples.realtime.find_by!(observed_at: missing_hour).destroy!

        assert_difference "WeatherSample.count", 1 do
          WeatherSyncJob.perform_now(now: Time.current + 1.hour)
        end
        assert location.weather_samples.realtime.exists?(observed_at: missing_hour)
        assert_equal confirmed_before, location.weather_samples.confirmed.order(:id).map(&:attributes)
        assert_no_difference "WeatherSample.count" do
          WeatherSyncJob.perform_now(now: Time.current + 1.hour)
          WeatherBackfillJob.perform_now(location_id: location.id)
        end
      end
    end
  end

  test "old backfill limits realtime history without truncating confirmed history" do
    location = domain_location
    oldest = @now - 120.days
    location.user.condition_logs.create!(headache: 5, nausea: 5, fatigue: 5, appetite: 5, clarity: 5,
      recorded_at: oldest)

    with_importer_stub { WeatherBackfillJob.perform_now(location_id: location.id, now: @now) }

    assert_equal (@now - 92.days).beginning_of_day,
      @calls.find { |call| call[:data_kind] == "realtime" }.fetch(:from)
    assert_equal oldest.beginning_of_hour - 24.hours,
      @calls.find { |call| call[:data_kind] == "confirmed" }.fetch(:from)
  end

  test "manual backfill repairs gaps older than the hourly sync lookback in both series" do
    original_importer = Weather::Importer.method(:call)
    client = Clients::OpenMeteoClient.new(http: OpenMeteoHTTP.new)
    @importer = ->(**arguments) { original_importer.call(**arguments, client: client) }
    location = nil

    travel_to Time.zone.local(2026, 9, 14, 12) do
      location = domain_location
      with_importer_stub { WeatherBackfillJob.perform_now(location_id: location.id) }
    end
    missing_hour = location.weather_samples.realtime.order(:observed_at).second.observed_at
    location.weather_samples.where(observed_at: missing_hour).destroy_all
    assert missing_hour < @now - 24.hours

    with_importer_stub do
      assert_difference "WeatherSample.count", 2 do
        WeatherBackfillJob.perform_now(location_id: location.id)
      end
      assert_equal %w[confirmed realtime], location.weather_samples.where(observed_at: missing_hour).map(&:data_kind).sort
      assert_no_difference "WeatherSample.count" do
        WeatherBackfillJob.perform_now(location_id: location.id)
      end
    end
  end

  private

  def with_importer_stub
    original = Weather::Importer.method(:call)
    Weather::Importer.define_singleton_method(:call, &@importer)
    yield
  ensure
    Weather::Importer.define_singleton_method(:call, original)
  end
end
