class AnalysesController < UserScopedController
  PRESSURE_DROP_THRESHOLD = -3.0
  HIGH_FATIGUE_THRESHOLD = 7

  def show
    @weather_history_start = current_user.location&.weather_history_start
    @weather_history_end = Time.current
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
    comparison_logs = @condition_logs.filter_map do |log|
      change = @weather_metrics.fetch(log.id)[:changes][6]
      [ log, change ] if change
    end
    @scatter = build_scatter(comparison_logs)
    @correlation = pressure_fatigue_correlation(comparison_logs)
    @threshold_summary = build_threshold_summary(comparison_logs)
    lag_logs = @condition_logs.filter_map do |log|
      changes = @weather_metrics.fetch(log.id)[:lagged_changes]
      [ log, changes ] if ConditionLog::PRESSURE_LAGS.all? { |lag| !changes[lag].nil? }
    end
    @lag_summary = ConditionLog::PRESSURE_LAGS.to_h do |lag|
      pairs = lag_logs.map { |log, changes| [ log, changes.fetch(lag) ] }
      [ lag, { correlation: pressure_fatigue_correlation(pairs), count: pairs.size } ]
    end
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

  def build_scatter(logs)
    return nil if logs.empty?

    extent = [ logs.map { |_, change| change.abs }.max, 1 ].max
    points = logs.map do |log, change|
      { x: (170 + change.fdiv(extent) * 130).round(1),
        y: (16 + (10 - log.fatigue).fdiv(9) * 116).round(1),
        date: log.recorded_at.in_time_zone.strftime("%Y/%m/%d %H:%M"),
        change: change, fatigue: log.fatigue }
    end
    { points: points, extent: extent, count: points.size }
  end

  def pressure_fatigue_correlation(logs)
    return nil if logs.size < 3

    mean_change = logs.sum { |_, change| change }.fdiv(logs.size)
    mean_fatigue = logs.sum { |log, _| log.fatigue }.fdiv(logs.size)
    deviations = logs.map { |log, change| [ change - mean_change, log.fatigue - mean_fatigue ] }
    change_variance = deviations.sum { |change, _| change**2 }
    fatigue_variance = deviations.sum { |_, fatigue| fatigue**2 }
    return nil if change_variance.zero? || fatigue_variance.zero?

    deviations.sum { |change, fatigue| change * fatigue } / Math.sqrt(change_variance * fatigue_variance)
  end

  def build_threshold_summary(logs)
    falling, other = logs.partition { |_, change| change <= PRESSURE_DROP_THRESHOLD }
    { falling: summarize_high_fatigue(falling), other: summarize_high_fatigue(other) }
  end

  def summarize_high_fatigue(logs)
    count = logs.size
    high_count = logs.count { |log, _| log.fatigue >= HIGH_FATIGUE_THRESHOLD }
    { count: count, high_count: high_count, percentage: count.positive? ? high_count.fdiv(count) * 100 : nil }
  end
end
