require "test_helper"
require_relative "../support/domain_records"

class DatabaseConstraintsTest < ActiveSupport::TestCase
  include DomainRecords

  {
    Location => %i[user_id latitude longitude],
    WeatherSample => %i[location_id observed_at data_kind],
    ConditionLog => %i[user_id recorded_at headache nausea fatigue appetite clarity],
    DailyLog => %i[user_id date wakeup_freshness sleep_minutes steps drank_alcohol screen_minutes]
  }.each do |model, fields|
    fields.each do |field|
      test "database requires #{model} #{field} without model validation" do
        record = build_record(model).tap(&:save!)
        assert_raises(ActiveRecord::NotNullViolation) { write_raw(record, field, nil) }
      end
    end
  end

  [ Location, WeatherSample, ConditionLog, DailyLog ].each do |model|
    foreign_key = model == WeatherSample ? :location_id : :user_id
    test "database rejects orphaned #{model}" do
      record = build_record(model).tap(&:save!)
      assert_raises(ActiveRecord::InvalidForeignKey) { write_raw(record, foreign_key, -1) }
    end
  end

  test "database protects parents when callbacks are bypassed" do
    build_record(WeatherSample).save!
    assert_raises(ActiveRecord::InvalidForeignKey) do
      User.transaction(requires_new: true) { domain_user.delete }
    end
    assert_raises(ActiveRecord::InvalidForeignKey) do
      Location.transaction(requires_new: true) { domain_location.delete }
    end
  end

  [ Location, WeatherSample, DailyLog ].each do |model|
    test "database rejects duplicate #{model} without model validation" do
      build_record(model).save!
      assert_raises(ActiveRecord::RecordNotUnique) do
        model.transaction(requires_new: true) { build_record(model).save!(validate: false) }
      end
    end
  end

  { ConditionLog => %i[headache nausea fatigue appetite clarity], DailyLog => [ :wakeup_freshness ] }.each do |model, fields|
    fields.each do |field|
      test "database enforces integer range for #{model} #{field}" do
        record = build_record(model).tap(&:save!)
        [ 0, 11, 1.5 ].each do |value|
          assert_raises(ActiveRecord::StatementInvalid) { write_raw(record, field, value) }
        end
        [ 1, 10 ].each do |value|
          write_raw(record, field, value)
          assert_equal value, record.reload.public_send(field)
        end
      end
    end
  end

  %i[sleep_minutes steps screen_minutes].each do |field|
    test "database enforces nonnegative integer for daily #{field}" do
      record = build_record(DailyLog).tap(&:save!)
      [ -1, 1.5 ].each do |value|
        assert_raises(ActiveRecord::StatementInvalid) { write_raw(record, field, value) }
      end
      write_raw(record, field, 0)
      assert_equal 0, record.reload.public_send(field)
    end
  end

  test "database rejects unknown weather kinds even during bulk import" do
    record = build_record(WeatherSample).tap(&:save!)
    [ -1, 2, 0.5 ].each do |value|
      assert_raises(ActiveRecord::StatementInvalid) { write_raw(record, :data_kind, value) }
    end
  end

  test "weather upsert updates only the matching series" do
    realtime = build_record(WeatherSample).tap(&:save!)
    confirmed = build_record(WeatherSample, data_kind: :confirmed, pressure_msl: "1014.5").tap(&:save!)
    attributes = { location_id: domain_location.id, observed_at: realtime.observed_at,
      data_kind: :realtime, pressure_msl: "1009.75" }

    assert_no_difference "WeatherSample.count" do
      2.times do
        WeatherSample.upsert_all([ attributes ], unique_by: %i[location_id observed_at data_kind])
      end
    end
    assert_equal BigDecimal("1009.75"), realtime.reload.pressure_msl
    assert_equal BigDecimal("1014.5"), confirmed.reload.pressure_msl
    assert_equal 60, realtime.humidity
  end

  private

  # Bypass Rails type casting as well as validations to exercise database checks.
  # Savepoints also keep the surrounding test usable after an error on PostgreSQL.
  def write_raw(record, field, value)
    record.class.transaction(requires_new: true) do
      record.class.connection_pool.with_connection do |connection|
        table = connection.quote_table_name(record.class.table_name)
        column = connection.quote_column_name(field)
        id = connection.quote_column_name(record.class.primary_key)
        connection.execute("UPDATE #{table} SET #{column} = #{connection.quote(value)} WHERE #{id} = #{connection.quote(record.id)}")
      end
    end
  end
end
