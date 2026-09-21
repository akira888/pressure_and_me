require "test_helper"
require_relative "../support/domain_records"

class DailyLogFormTest < ActiveSupport::TestCase
  include DomainRecords

  def form_record(**overrides)
    build_record(DailyLog, sleep_hours: "6", sleep_remainder_minutes: "30",
      screen_hours: "8", screen_remainder_minutes: "15", **overrides)
  end

  test "hours and minutes are saved as total minutes and can be restored" do
    record = form_record
    assert record.save(context: :form)
    saved = DailyLog.find(record.id)
    assert_equal 390, saved.sleep_minutes
    assert_equal 495, saved.screen_minutes
    assert_equal 6, saved.sleep_hours
    assert_equal 30, saved.sleep_remainder_minutes
    assert_equal 8, saved.screen_hours
    assert_equal 15, saved.screen_remainder_minutes
  end

  test "zero duration and a no answer are valid" do
    record = form_record(sleep_hours: "0", sleep_remainder_minutes: "0",
      screen_hours: "0", screen_remainder_minutes: "0", drank_alcohol: "0")
    assert record.save(context: :form)
    assert_equal 0, record.reload.sleep_minutes
    assert_equal false, record.drank_alcohol
  end

  %i[sleep screen].each do |duration|
    test "#{duration} parts reject blanks negative fractional and non numeric values" do
      [ nil, "", "abc", "-1", "1.5" ].each do |value|
        assert_not form_record("#{duration}_hours".to_sym => value).valid?(:form)
        assert_not form_record("#{duration}_remainder_minutes".to_sym => value).valid?(:form)
      end
      assert_not form_record("#{duration}_remainder_minutes".to_sym => "60").valid?(:form)
    end
  end

  test "invalid updates preserve stored totals and retain submitted parts" do
    record = form_record
    record.save!(context: :form)
    record.assign_attributes(sleep_hours: "abc", screen_remainder_minutes: "60")
    assert_not record.save(context: :form)
    assert_equal "abc", record.sleep_hours
    assert_equal "60", record.screen_remainder_minutes
    assert_equal 390, DailyLog.find(record.id).sleep_minutes
  end

  test "alcohol answer cannot be an arbitrary string" do
    assert_not form_record(drank_alcohol: "garbage").valid?(:form)
  end
end
