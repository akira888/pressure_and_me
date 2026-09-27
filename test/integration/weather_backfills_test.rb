require "test_helper"

class WeatherBackfillsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    travel_to Time.zone.local(2026, 9, 27, 10, 37)
    @user = User.create!
    @base = "/u/#{@user.uuid}"
  end

  test "analysis shows historical range and a POST button without enqueueing" do
    @user.create_location!(latitude: 35, longitude: 139)
    @user.condition_logs.create!(recorded_at: Time.zone.local(2026, 8, 1, 9, 37),
      headache: 5, nausea: 5, fatigue: 5, appetite: 5, clarity: 5)

    assert_no_enqueued_jobs do
      get "#{@base}/analysis"
    end
    assert_response :success
    assert_select ".weather-backfill", text: /2026\/07\/31 09:00.*2026\/09\/27 10:37/m
    assert_select "form[action='#{@base}/weather_backfill'][method=post] button", text: "過去の気象データを再取得"
  end

  test "POST enqueues only the UUID users location and ignores supplied scope" do
    location = @user.create_location!(latitude: 35, longitude: 139)
    other = User.create!.create_location!(latitude: 34, longitude: 135)

    assert_enqueued_jobs 1, only: WeatherBackfillJob do
      assert_enqueued_with(job: WeatherBackfillJob, args: [ { location_id: location.id } ]) do
        post "#{@base}/weather_backfill", params: { location_id: other.id, from: "2000-01-01" }
      end
    end
    assert_response :see_other
    assert_redirected_to "#{@base}/analysis"
    follow_redirect!
    assert_select "[role=status]", text: /再取得を予約しました/
  end

  test "missing location shows guidance and cannot enqueue an all location backfill" do
    get "#{@base}/analysis"
    assert_select ".weather-backfill", text: /地点が未登録/
    assert_select "form[action='#{@base}/weather_backfill']", count: 0
    assert_no_enqueued_jobs do
      post "#{@base}/weather_backfill"
    end
    assert_response :see_other
    follow_redirect!
    assert_select "[role=alert]", text: /地点が未登録/
  end

  test "unknown UUID cannot enqueue a backfill" do
    assert_no_enqueued_jobs do
      post "/u/#{SecureRandom.uuid}/weather_backfill"
    end
    assert_response :not_found
  end
end
