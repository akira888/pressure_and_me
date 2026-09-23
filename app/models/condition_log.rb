class ConditionLog < ApplicationRecord
  SCORES = %i[headache nausea fatigue appetite clarity].freeze

  belongs_to :user

  validates :recorded_at, presence: true
  validates :headache, :nausea, :fatigue, :appetite, :clarity,
    numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 10 }

  def weather_metrics(data_kind: :realtime, location: user.location)
    empty_metrics = { pressure: nil, changes: {}, ranges: {} }
    return empty_metrics unless location

    hour = recorded_at.beginning_of_hour
    samples = location.weather_samples.public_send(data_kind).where(observed_at: hour - 24.hours..hour)
      .where.not(pressure_msl: nil).index_by(&:observed_at)
    current = samples[hour]
    return empty_metrics.merge(ranges: pressure_ranges(samples, hour)) unless current

    changes = [ 3, 6, 12, 24 ].to_h do |hours|
      previous = samples[hour - hours.hours]
      [ hours, previous && current.pressure_msl.to_f - previous.pressure_msl.to_f ]
    end
    { pressure: current.pressure_msl.to_f, changes: changes, ranges: pressure_ranges(samples, hour) }
  end

  private

  def pressure_ranges(samples, hour)
    [ 6, 24 ].to_h do |hours|
      values = samples.values_at(*((hour - hours.hours)..hour).step(1.hour)).compact.map { |sample| sample.pressure_msl.to_f }
      [ hours, values.any? ? values.max - values.min : nil ]
    end
  end
end
