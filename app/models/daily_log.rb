class DailyLog < ApplicationRecord
  belongs_to :user

  %i[sleep screen].each do |duration|
    attr_writer :"#{duration}_hours", :"#{duration}_remainder_minutes"

    define_method("#{duration}_hours") do
      if instance_variable_defined?("@#{duration}_hours")
        instance_variable_get("@#{duration}_hours")
      else
        public_send("#{duration}_minutes")&.div(60)
      end
    end

    define_method("#{duration}_remainder_minutes") do
      if instance_variable_defined?("@#{duration}_remainder_minutes")
        instance_variable_get("@#{duration}_remainder_minutes")
      else
        public_send("#{duration}_minutes")&.%(60)
      end
    end

    validates :"#{duration}_hours", on: :form,
      numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :"#{duration}_remainder_minutes", on: :form,
      numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than: 60 }
  end

  before_validation :combine_duration_parts, on: :form
  validate :alcohol_answer_is_explicit, on: :form

  validates :date, presence: true, uniqueness: { scope: :user_id }
  validates :wakeup_freshness,
    numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 10 }
  validates :sleep_minutes, :steps, :screen_minutes,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :drank_alcohol, inclusion: { in: [ true, false ] }

  private

  def combine_duration_parts
    %i[sleep screen].each do |duration|
      hours = Integer(public_send("#{duration}_hours").to_s, 10, exception: false)
      minutes = Integer(public_send("#{duration}_remainder_minutes").to_s, 10, exception: false)
      self["#{duration}_minutes"] = if hours && minutes && hours >= 0 && minutes.between?(0, 59)
        hours * 60 + minutes
      end
    end
  end

  def alcohol_answer_is_explicit
    unless [ true, false, 0, 1, "0", "1" ].include?(drank_alcohol_before_type_cast)
      errors.add(:drank_alcohol, :inclusion)
    end
  end
end
