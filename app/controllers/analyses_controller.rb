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
  end
end
