require "test_helper"
require_relative "../support/domain_records"

class WeatherTriggersTest < ActiveSupport::TestCase
  include DomainRecords
  include ActiveJob::TestHelper

  test "committed location registration enqueues only its backfill" do
    location = build_record(Location)
    assert_enqueued_jobs 1, only: WeatherBackfillJob do
      location.save!
    end
    assert_enqueued_with(job: WeatherBackfillJob, args: [ { location_id: location.id } ])
    assert_equal 0, WeatherSample.count
  end

  test "reading or updating an existing location does not enqueue backfill" do
    location = domain_location
    clear_enqueued_jobs
    assert_no_enqueued_jobs do
      Location.find(location.id)
      location.update!(latitude: "35.7")
    end
  end

  test "rolled back registration does not enqueue backfill" do
    user = domain_user
    assert_no_enqueued_jobs do
      Location.transaction(requires_new: true) do
        Location.create!(user: user, latitude: 35, longitude: 139)
        raise ActiveRecord::Rollback
      end
    end
    assert_nil user.reload.location
  end

  test "supervisor startup enqueues sync without importing inline" do
    domain_location
    clear_enqueued_jobs
    assert_enqueued_with(job: WeatherSyncJob, args: []) do
      SolidQueue::Supervisor.lifecycle_hooks.fetch(:start).each { |hook| hook.call(nil) }
    end
    assert_equal 0, WeatherSample.count
  end
end
