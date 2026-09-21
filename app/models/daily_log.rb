class DailyLog < ApplicationRecord
  belongs_to :user

  validates :date, presence: true, uniqueness: { scope: :user_id }
  validates :wakeup_freshness,
    numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 10 }
  validates :sleep_minutes, :steps, :screen_minutes,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :drank_alcohol, inclusion: { in: [ true, false ] }
end
