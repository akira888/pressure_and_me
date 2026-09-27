require "test_helper"

class RecordingTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 9, 21, 10, 37)
    @user = User.create!
    @other = User.create!
    @base = "/u/#{@user.uuid}"
    @scores = { headache: 1, nausea: 2, fatigue: 3, appetite: 8, clarity: 9 }
    @daily = { wakeup_freshness: 7, sleep_hours: "6", sleep_remainder_minutes: "30",
      steps: "4000", drank_alcohol: "0", screen_hours: "8", screen_remainder_minutes: "15" }
  end

  test "three tabs load without creating logs and keep the UUID in their links" do
    assert_no_difference [ "ConditionLog.count", "DailyLog.count" ] do
      [ @base, "#{@base}/daily_log", "#{@base}/analysis" ].each do |path|
        get path
        assert_response :success
        assert_select "nav a[href='#{@base}']", text: "体調"
        assert_select "nav a[href='#{@base}/daily_log']", text: "朝の記録"
        assert_select "nav a[href='#{@base}/analysis']", text: "分析"
        assert_select "nav a[aria-current='page']", count: 1
      end
    end
  end

  test "analysis shows recent condition metrics when hourly weather exists" do
    location = @user.create_location!(latitude: 35, longitude: 139)
    recorded_at = Time.zone.local(2026, 9, 21, 10, 37)
    @user.condition_logs.create!(headache: 4, nausea: 3, fatigue: 8, appetite: 5, clarity: 6,
      recorded_at: recorded_at)
    location.weather_samples.create!(observed_at: recorded_at.beginning_of_hour,
      data_kind: :realtime, pressure_msl: 1012)
    location.weather_samples.create!(observed_at: recorded_at.beginning_of_hour - 3.hours,
      data_kind: :realtime, pressure_msl: 1009)

    get "#{@base}/analysis"
    assert_response :success
    assert_select ".analysis-item", count: 1
    assert_select ".analysis-item", text: /1012\.0 hPa/
    assert_select ".analysis-item", text: /だるさ 8/
    assert_select ".analysis-item", text: /気圧レンジ（6h \/ 24h）/
    assert_select ".trend-grid", text: /だるさ/
    assert_select "svg.analysis-chart[aria-label='気圧とだるさの推移']"
    assert_select ".page-intro p.eyebrow", text: "毎日の記録を、これからの気づきに。"
    assert_select ".page-intro", text: /気象データは毎時更新され/
  end

  test "analysis shows monthly high score ratios with the eligible sample count" do
    location = @user.create_location!(latitude: 35, longitude: 139)
    2.times do |index|
      recorded_at = Time.zone.local(2026, 9, 20 + (index * 2), 10, 37)
      @user.condition_logs.create!(headache: index.zero? ? 8 : 4, nausea: 5, fatigue: 7,
        appetite: 5, clarity: 5, recorded_at: recorded_at)
      0.upto(24) do |hours_ago|
        location.weather_samples.create!(observed_at: recorded_at.beginning_of_hour - hours_ago.hours,
          data_kind: :confirmed, pressure_msl: 1010)
      end
    end

    get "#{@base}/analysis"
    assert_response :success
    assert_select ".monthly-summary", text: /頭痛.*50\.0%.*n=2/
    assert_select ".monthly-summary", text: /だるさ.*100\.0%.*n=2/
  end

  test "analysis plots six hour pressure change against fatigue and retains the existing trend" do
    location = @user.create_location!(latitude: 35, longitude: 139)
    [ [ 3.days.ago, 8, 1010, 1014 ], [ 2.days.ago, 2, 1010, 1006 ], [ 1.day.ago, 5, 1010, nil ] ].each do |time, fatigue, current, previous|
      @user.condition_logs.create!(@scores.merge(recorded_at: time, fatigue: fatigue))
      hour = time.beginning_of_hour
      location.weather_samples.create!(observed_at: hour, data_kind: :realtime, pressure_msl: current)
      location.weather_samples.create!(observed_at: hour - 6.hours, data_kind: :realtime, pressure_msl: previous) if previous
    end

    get "#{@base}/analysis"

    assert_response :success
    assert_select "svg.analysis-chart[aria-label='気圧とだるさの推移']"
    assert_select ".pressure-fatigue-scatter", text: /n=2/
    assert_select "svg[aria-label='直近6時間の気圧変化とだるさの散布図'] circle.scatter-point", count: 2
    assert_select "circle.scatter-point[cx='40.0'][cy='41.8'] title", text: /-4\.0 hPa.*だるさ 8/
    assert_select "circle.scatter-point[cx='300.0'][cy='119.1'] title", text: /\+4\.0 hPa.*だるさ 2/
    assert_select ".pressure-fatigue-scatter", text: /気圧低下.*0.*気圧上昇/m
  end

  test "analysis explains when six hour pressure changes are unavailable" do
    @user.condition_logs.create!(@scores.merge(recorded_at: Time.current))

    get "#{@base}/analysis"

    assert_response :success
    assert_select ".pressure-fatigue-scatter", text: /6時間前と記録時点の気圧データが揃うと表示されます/
    assert_select "svg[aria-label='直近6時間の気圧変化とだるさの散布図']", count: 0
  end

  test "unknown UUID cannot read or write records" do
    base = "/u/#{SecureRandom.uuid}"
    [ base, "#{base}/daily_log", "#{base}/analysis" ].each do |path|
      get path
      assert_response :not_found
    end
    assert_no_difference [ "ConditionLog.count", "DailyLog.count" ] do
      post "#{base}/condition_logs", params: { condition_log: @scores.merge(recorded_at: Time.current) }
      assert_response :not_found
      put "#{base}/daily_log", params: { daily_log: @daily }
      assert_response :not_found
    end
  end

  test "first condition form has five sliders with a current timestamp" do
    get @base
    assert_select "input[type=range][min='1'][max='10'][value='5']", count: 5
    assert_select "input[name='condition_log[recorded_at]'][value='2026-09-21T10:37']"
  end

  test "condition defaults use only this users latest log" do
    @user.condition_logs.create!(@scores.merge(recorded_at: 2.hours.ago))
    @other.condition_logs.create!(@scores.merge(fatigue: 10, recorded_at: 1.hour.ago))
    get @base
    assert_select "input[name='condition_log[fatigue]'][value='3']"
    assert_select "input[name='condition_log[appetite]'][value='8']"
    assert_select "input[name='condition_log[recorded_at]'][value='2026-09-21T10:37']"
  end

  test "condition submissions insert each time and ignore supplied user and record IDs" do
    assert_difference "@user.condition_logs.count", 2 do
      2.times do
        post "#{@base}/condition_logs", params: {
          condition_log: @scores.merge(recorded_at: "2026-09-21T10:37", user_id: @other.id, id: 123)
        }
        assert_redirected_to @base
        assert_response :see_other
      end
    end
    assert_equal 0, @other.condition_logs.count
    assert_equal Time.current, @user.condition_logs.last.recorded_at
    follow_redirect!
    assert_select "[role=status]", text: /体調を記録しました/
  end

  test "invalid conditions show errors and preserve entered scores without saving" do
    assert_no_difference "ConditionLog.count" do
      post "#{@base}/condition_logs", params: { condition_log: @scores.merge(headache: 11, recorded_at: "") }
    end
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /頭痛/
    assert_select "[role=alert]", text: /記録時刻/
    assert_select "input[name='condition_log[fatigue]'][value='3']"
  end

  test "morning form does not inherit yesterday and does not select an alcohol answer" do
    @user.daily_logs.create!(date: Date.yesterday, wakeup_freshness: 10, sleep_minutes: 500,
      screen_minutes: 100, steps: 100, drank_alcohol: true)
    get "#{@base}/daily_log"
    assert_select "input[name='daily_log[wakeup_freshness]'][value='5']"
    assert_select "input[name='daily_log[sleep_hours]'][value='6']"
    assert_select "input[name='daily_log[sleep_remainder_minutes]'][value='30']"
    assert_select "input[name='daily_log[steps]'][value='4000']"
    assert_select "input[name='daily_log[screen_hours]'][value='8']"
    assert_select "input[name='daily_log[screen_remainder_minutes]'][value='0']"
    assert_select "input[name='daily_log[drank_alcohol]'][checked]", count: 0
  end

  test "PUT creates then updates todays log scoped to the UUID" do
    @other.daily_logs.create!(date: Date.current, wakeup_freshness: 1, sleep_minutes: 0,
      screen_minutes: 0, steps: 0, drank_alcohol: true)
    assert_difference "@user.daily_logs.count", 1 do
      put "#{@base}/daily_log", params: { daily_log: @daily.merge(user_id: @other.id, date: Date.yesterday) }
      assert_redirected_to "#{@base}/daily_log"
    end
    log = @user.daily_logs.sole
    assert_equal Date.current, log.date
    assert_equal 390, log.sleep_minutes
    assert_equal 495, log.screen_minutes
    assert_equal false, log.drank_alcohol
    assert_no_difference "DailyLog.count" do
      put "#{@base}/daily_log", params: { daily_log: @daily.merge(steps: "9000", drank_alcohol: "1") }
      assert_response :see_other
    end
    assert_equal 9000, log.reload.steps
    assert log.drank_alcohol
    assert_equal 0, @other.daily_logs.sole.steps
    follow_redirect!
    assert_select "input[name='daily_log[sleep_hours]'][value='6']"
    assert_select "input[name='daily_log[sleep_remainder_minutes]'][value='30']"
    assert_select "input[name='daily_log[wakeup_freshness]'][value='7']"
  end

  test "Tokyo midnight starts a new daily log" do
    travel_to Time.utc(2026, 9, 21, 14, 59) do
      put "#{@base}/daily_log", params: { daily_log: @daily }
    end
    travel_to Time.utc(2026, 9, 21, 15, 1) do
      put "#{@base}/daily_log", params: { daily_log: @daily }
    end
    assert_equal [ Date.new(2026, 9, 21), Date.new(2026, 9, 22) ], @user.daily_logs.order(:date).pluck(:date)
  end

  test "invalid daily update leaves saved values intact and shows the submitted parts" do
    put "#{@base}/daily_log", params: { daily_log: @daily }
    put "#{@base}/daily_log", params: { daily_log: @daily.merge(sleep_remainder_minutes: "60", steps: "-1", drank_alcohol: "") }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /睡眠時間/
    assert_select "input[name='daily_log[sleep_remainder_minutes]'][value='60']"
    assert_equal 390, @user.daily_logs.sole.sleep_minutes
    assert_equal 4000, @user.daily_logs.sole.steps
  end
end
