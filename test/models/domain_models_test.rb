require "test_helper"
require_relative "../support/domain_records"

class DomainModelsTest < ActiveSupport::TestCase
  include DomainRecords

  test "user needs no profile or authentication fields" do
    assert User.new.save
  end

  test "associations connect each record to its owner" do
    weather = build_record(WeatherSample).tap(&:save!)
    condition = build_record(ConditionLog).tap(&:save!)
    daily = build_record(DailyLog).tap(&:save!)

    assert_equal domain_location, domain_user.reload.location
    assert_equal domain_user, domain_location.user
    assert_equal [ weather ], domain_location.weather_samples.to_a
    assert_equal domain_location, weather.location
    assert_equal [ condition ], domain_user.condition_logs.to_a
    assert_equal domain_user, condition.user
    assert_equal [ daily ], domain_user.daily_logs.to_a
    assert_equal domain_user, daily.user
  end

  test "user can only have one location" do
    domain_location
    duplicate = build_record(Location)
    assert_not duplicate.valid?
    assert duplicate.errors.added?(:user_id, :taken, value: domain_user.id)
    assert build_record(Location, user: User.create!).save
  end

  [ Location, WeatherSample, ConditionLog, DailyLog ].each do |model|
    association = model == WeatherSample ? :location : :user
    test "#{model} requires an existing #{association}" do
      record = build_record(model, association => nil)
      assert_not record.valid?
      assert record.errors[association].present?
      record.public_send("#{association}_id=", -1)
      assert_not record.valid?
      assert record.errors[association].present?
    end
  end

  %i[latitude longitude].each do |coordinate|
    test "location requires numeric #{coordinate}" do
      [ nil, "", "abc" ].each do |value|
        record = build_record(Location, coordinate => value)
        assert_not record.valid?, value.inspect
        assert record.errors[coordinate].present?
      end
    end
  end

  test "coordinates and weather decimals survive persistence" do
    weather = build_record(WeatherSample).tap(&:save!).reload
    assert_equal BigDecimal("35.681236"), domain_location.reload.latitude
    assert_equal BigDecimal("139.767125"), domain_location.longitude
    assert_equal BigDecimal("1013.25"), weather.pressure_msl
    assert_equal BigDecimal("25.125"), weather.temperature
    assert_equal BigDecimal("0.125"), weather.precipitation
  end

  test "weather enum has stable integer mappings and rejects unknown values" do
    assert_equal({ "realtime" => 0, "confirmed" => 1 }, WeatherSample.data_kinds)
    [ nil, "forecast", 2 ].each do |value|
      record = build_record(WeatherSample, data_kind: value)
      assert_not record.valid?
      assert record.errors[:data_kind].present?
    end
  end

  test "weather series coexist but each location time and kind is unique" do
    realtime = build_record(WeatherSample).tap(&:save!)
    confirmed = build_record(WeatherSample, data_kind: :confirmed).tap(&:save!)
    assert_equal [ realtime ], WeatherSample.realtime.to_a
    assert_equal [ confirmed ], WeatherSample.confirmed.to_a
    duplicate = build_record(WeatherSample)
    assert_not duplicate.valid?
    assert duplicate.errors[:observed_at].present?
    assert build_record(WeatherSample, observed_at: realtime.observed_at + 1.hour).save
    other_location = build_record(Location, user: User.create!).tap(&:save!)
    assert build_record(WeatherSample, location: other_location).save
  end

  test "weather values can be missing" do
    assert build_record(WeatherSample, pressure_msl: nil, temperature: nil,
      humidity: nil, precipitation: nil, weather_code: nil).save
  end

  test "weather values must be numeric when supplied" do
    %i[pressure_msl temperature precipitation humidity weather_code].each do |field|
      record = build_record(WeatherSample, field => "abc")
      assert_not record.valid?
      assert record.errors[field].present?
    end
    %i[humidity weather_code].each do |field|
      assert_not build_record(WeatherSample, field => 1.5).valid?
    end
  end

  { WeatherSample => :observed_at, ConditionLog => :recorded_at, DailyLog => :date }.each do |model, field|
    test "#{model} requires #{field}" do
      record = build_record(model, field => nil)
      assert_not record.valid?
      assert record.errors[field].present?
    end
  end

  test "condition logs allow repeated timestamps" do
    first = build_record(ConditionLog).tap(&:save!)
    second = build_record(ConditionLog).tap(&:save!)
    assert_not_equal first.id, second.id
    assert_equal first.recorded_at, second.recorded_at
  end

  { ConditionLog => %i[headache nausea fatigue appetite clarity], DailyLog => [ :wakeup_freshness ] }.each do |model, fields|
    fields.each do |field|
      test "#{model} #{field} is an integer score from 1 to 10" do
        [ nil, "", "abc", 0, 11, 1.5 ].each do |value|
          record = build_record(model, field => value)
          assert_not record.valid?, value.inspect
          assert record.errors[field].present?
        end
        [ 1, 10 ].each { |value| assert build_record(model, field => value).valid? }
      end
    end
  end

  %i[sleep_minutes steps screen_minutes].each do |field|
    test "daily #{field} is a nonnegative integer" do
      [ nil, "", "abc", -1, 1.5 ].each do |value|
        record = build_record(DailyLog, field => value)
        assert_not record.valid?, value.inspect
        assert record.errors[field].present?
      end
      assert build_record(DailyLog, field => 0).valid?
    end
  end

  test "alcohol answer accepts both yes and no but requires an answer" do
    [ true, false ].each { |value| assert build_record(DailyLog, drank_alcohol: value).valid? }
    [ nil, "" ].each { |value| assert_not build_record(DailyLog, drank_alcohol: value).valid? }
  end

  test "daily logs are unique per user and date and can be updated" do
    daily = build_record(DailyLog).tap(&:save!)
    duplicate = build_record(DailyLog)
    assert_not duplicate.valid?
    assert duplicate.errors[:date].present?
    assert build_record(DailyLog, user: User.create!).save
    assert build_record(DailyLog, date: daily.date + 1.day).save
    assert_no_difference "DailyLog.count" do
      daily.update!(sleep_minutes: 480, drank_alcohol: true)
    end
    assert_equal 480, daily.reload.sleep_minutes
    assert daily.drank_alcohol
  end

  test "record times preserve the instant and use Tokyo date boundaries" do
    record = build_record(ConditionLog, recorded_at: Time.utc(2026, 9, 20, 15, 30)).tap(&:save!).reload
    assert_equal Time.utc(2026, 9, 20, 15, 30), record.recorded_at
    assert_equal Date.new(2026, 9, 21), record.recorded_at.to_date
  end

  test "parents with records cannot be destroyed implicitly" do
    weather = build_record(WeatherSample).tap(&:save!)
    assert_not domain_user.destroy
    assert_not domain_location.destroy
    assert WeatherSample.exists?(weather.id)
    assert User.exists?(domain_user.id)
    assert Location.exists?(domain_location.id)
  end

  [ ConditionLog, DailyLog ].each do |model|
    test "user with #{model} cannot be destroyed" do
      record = build_record(model).tap(&:save!)
      assert_not domain_user.destroy
      assert model.exists?(record.id)
    end
  end
end
