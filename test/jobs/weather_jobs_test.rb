require "test_helper"
require_relative "../support/domain_records"

class WeatherJobsTest < ActiveSupport::TestCase
  include DomainRecords
  include ActiveJob::TestHelper

  setup do
    @now = Time.zone.local(2026, 9, 21, 12)
    @calls = []
    calls = @calls
    @importer = ->(**arguments) { calls << arguments; arguments }
  end

  test "backfill imports seven days for both series at every location" do
    first = domain_location
    second = build_record(Location, user: User.create!, latitude: "34.693738", longitude: "135.502165").tap(&:save!)

    with_importer_stub do
      WeatherBackfillJob.perform_now(now: @now)
    end

    assert_equal 4, @calls.size
    assert_equal [ first, first, second, second ], @calls.map { |call| call.fetch(:location) }
    assert_equal %w[realtime confirmed realtime confirmed], @calls.map { |call| call.fetch(:data_kind) }
    @calls.each do |call|
      assert_equal @now - 7.days, call.fetch(:from)
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

  test "sync backfills seven days for a series with no samples" do
    location = domain_location
    WeatherSample.create!(location: location, observed_at: @now - 2.hours, data_kind: :realtime)

    with_importer_stub do
      WeatherSyncJob.perform_now(now: @now)
    end

    confirmed = @calls.find { |call| call.fetch(:data_kind) == "confirmed" }
    assert_equal @now - 7.days, confirmed.fetch(:from)
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

  private

  def with_importer_stub
    original = Weather::Importer.method(:call)
    Weather::Importer.define_singleton_method(:call, &@importer)
    yield
  ensure
    Weather::Importer.define_singleton_method(:call, original)
  end
end
