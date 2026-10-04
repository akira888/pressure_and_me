require "application_system_test_case"

class RecordingTest < ApplicationSystemTestCase
  setup do
    @user = User.create!
    @base = "/u/#{@user.uuid}"
  end

  test "condition slider updates in the browser and its value survives saving" do
    visit @base

    within find(".score-row", text: "だるさ") do
      find("input[type=range]").send_keys(:end)
      assert_selector "output", text: "10"
    end
    click_button "体調を記録する"

    assert_text "体調を記録しました。"
    assert_selector "input[name='condition_log[fatigue]'][value='10']"
    assert_equal 10, @user.condition_logs.sole.fatigue
  end

  test "morning record retains entered duration and alcohol choice" do
    visit "#{@base}/daily_log"
    fill_in "睡眠時間（時間）", with: "7"
    fill_in "睡眠時間（分）", with: "25"
    fill_in "歩数", with: "5600"
    choose "いいえ"
    fill_in "画面時間（時間）", with: "4"
    fill_in "画面時間（分）", with: "10"
    click_button "朝の記録を保存する"

    assert_text "朝の記録を保存しました。"
    assert_field "睡眠時間（時間）", with: "7"
    assert_field "睡眠時間（分）", with: "25"
    assert_checked_field "いいえ"
    assert_equal 445, @user.daily_logs.sole.sleep_minutes
  end

  test "analysis navigation shows the scatter and threshold comparison" do
    location = @user.create_location!(latitude: 35, longitude: 139)
    [ [ 19, 1014, 8 ], [ 20, 1010, 4 ] ].each do |day, previous_pressure, fatigue|
      hour = Time.zone.local(2026, 9, day, 10)
      @user.daily_logs.create!(date: hour.to_date, sleep_minutes: day == 19 ? 300 : 420,
        wakeup_freshness: 5, steps: 0, drank_alcohol: false, screen_minutes: 0)
      @user.condition_logs.create!(recorded_at: hour + 37.minutes,
        headache: 5, nausea: 5, fatigue: fatigue, appetite: 5, clarity: 5)
      location.weather_samples.create!(observed_at: hour, data_kind: :realtime, pressure_msl: 1010)
      location.weather_samples.create!(observed_at: hour - 6.hours, data_kind: :realtime,
        pressure_msl: previous_pressure)
    end

    visit @base
    click_link "分析"

    assert_selector "svg[aria-label='直近6時間の気圧変化とだるさの散布図'] circle.scatter-point", count: 2
    within ".threshold-fall" do
      assert_text "1/1件"
      assert_text "100.0%"
    end
    within ".threshold-other" do
      assert_text "0/1件"
      assert_text "0.0%"
    end
    within ".combined-analysis" do
      assert_selector "tbody tr", count: 4
      within "tr[data-group='falling_short']" do
        assert_text "1/1件"
        assert_text "100.0%"
      end
      within "tr[data-group='other_long']" do
        assert_text "0/1件"
        assert_text "0.0%"
      end
    end
    within ".lag-analysis" do
      assert_selector "tbody tr", count: 4
      assert_text "4つの時間帯すべての気圧が揃った記録"
    end
  end
end
