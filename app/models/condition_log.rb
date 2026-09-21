class ConditionLog < ApplicationRecord
  SCORES = %i[headache nausea fatigue appetite clarity].freeze

  belongs_to :user

  validates :recorded_at, presence: true
  validates :headache, :nausea, :fatigue, :appetite, :clarity,
    numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 10 }
end
