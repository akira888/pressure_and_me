require "test_helper"

class ConditionLogAnalysisTest < ActiveSupport::TestCase
  setup do
    @user = User.create!
    @location = @user.create_location!(latitude: 35.0, longitude: 139.0)
    @recorded_at = Time.zone.local(2026, 9, 23, 10, 37)
    @log = @user.condition_logs.create!(headache: 5, nausea: 5, fatigue: 7,
      appetite: 5, clarity: 4, recorded_at: @recorded_at)
  end

  test "uses the latest hourly sample at or before the condition log" do
    add_sample(0, 1012)
    add_sample(3, 1009)
    add_sample(6, 1008)
    assert_equal 1012.0, @log.weather_metrics[:pressure]
    assert_equal 3.0, @log.weather_metrics[:changes][3]
    assert_equal 4.0, @log.weather_metrics[:changes][6]
  end

  test "returns nil changes when the requested hourly sample is missing" do
    add_sample(0, 1012)
    add_sample(3, 1009)

    metrics = @log.weather_metrics
    assert_equal 1012.0, metrics[:pressure]
    assert_equal 3.0, metrics[:changes][3]
    assert_nil metrics[:changes][6]
    assert_equal 3.0, metrics[:ranges][24]
  end

  test "keeps realtime and confirmed series separate" do
    add_sample(0, 1012, :realtime)
    add_sample(3, 1009, :realtime)
    add_sample(0, 1020, :confirmed)
    add_sample(3, 1010, :confirmed)

    assert_equal 1012.0, @log.weather_metrics[:pressure]
    assert_equal 1020.0, @log.weather_metrics(data_kind: :confirmed)[:pressure]
  end

  test "measures six hour pressure changes ending at each earlier lag" do
    { 0 => 1008, 3 => 1007, 6 => 1012, 9 => 1009, 12 => 1010, 18 => 1013 }.each do |hours_ago, pressure|
      add_sample(hours_ago, pressure)
    end

    assert_equal({ 0 => -4.0, 3 => -2.0, 6 => 2.0, 12 => -3.0 },
      @log.weather_metrics[:lagged_changes])
    @location.weather_samples.find_by!(observed_at: @recorded_at.beginning_of_hour - 9.hours,
      data_kind: :realtime).destroy!
    assert_nil @log.weather_metrics[:lagged_changes][3]
    assert_equal(-4.0, @log.weather_metrics[:lagged_changes][0])
  end

  test "confirmed monthly analysis requires every hour in the 24 hour window" do
    0.upto(24) do |hours_ago|
      add_sample(hours_ago, 1010 + hours_ago, :confirmed)
    end

    assert @log.weather_data_complete?(data_kind: :confirmed)

    @location.weather_samples.find_by!(
      observed_at: @recorded_at.beginning_of_hour - 12.hours, data_kind: :confirmed
    ).update!(pressure_msl: nil)

    assert_not @log.weather_data_complete?(data_kind: :confirmed)
  end

  private

  def add_sample(hours_ago, pressure, data_kind = :realtime)
    @location.weather_samples.create!(observed_at: @recorded_at.beginning_of_hour - hours_ago.hours,
      data_kind: data_kind, pressure_msl: pressure)
  end
end
