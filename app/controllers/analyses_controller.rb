class AnalysesController < UserScopedController
  def show
    @condition_logs = current_user.condition_logs.order(recorded_at: :desc).limit(20)
    @weather_metrics = @condition_logs.to_h { |log| [ log.id, log.weather_metrics ] }
    @monthly_condition_logs = current_user.condition_logs.order(recorded_at: :desc).select do |log|
      log.weather_data_complete?(data_kind: :confirmed)
    end
    @monthly_summary = ConditionLog::SCORES.to_h do |score|
      high_count = @monthly_condition_logs.count { |log| log.public_send(score) >= 7 }
      [ score, { high_count: high_count, count: @monthly_condition_logs.size } ]
    end
    @score_summary = ConditionLog::SCORES.to_h do |score|
      values = current_user.condition_logs.where.not(score => nil).pluck(score)
      [ score, { average: values.any? ? values.sum.to_f / values.size : nil, count: values.size } ]
    end
    @chart = build_chart(@condition_logs.reverse.filter_map do |log|
      metrics = @weather_metrics.fetch(log.id)
      [ log, metrics ] if metrics[:pressure]
    end)
  end

  private

  def build_chart(chart_logs)
    return nil if chart_logs.empty?

    pressures = chart_logs.map { |_, metrics| metrics[:pressure] }
    min_pressure = pressures.min
    pressure_span = [ pressures.max - min_pressure, 1 ].max
    last_index = [ chart_logs.length - 1, 1 ].max
    points_for = lambda do |value_for|
      chart_logs.each_with_index.map do |(log, metrics), index|
        x = (index.fdiv(last_index) * 320).round(1)
        y = (130 - (value_for.call(log, metrics) * 100)).round(1)
        "#{x},#{y}"
      end.join(" ")
    end
    { pressure_points: points_for.call(->(_, metrics) { (metrics[:pressure] - min_pressure) / pressure_span }),
      fatigue_points: points_for.call(->(log, _) { (log.fatigue - 1).fdiv(9) }) }
  end
end
