class AnalysesController < UserScopedController
  def show
    @condition_logs = current_user.condition_logs.order(recorded_at: :desc).limit(20)
    @weather_metrics = @condition_logs.to_h { |log| [ log.id, log.weather_metrics ] }
    @monthly_condition_logs = current_user.condition_logs.order(recorded_at: :desc).select do |log|
      log.weather_data_complete?(data_kind: :confirmed)
    end
    @score_summary = ConditionLog::SCORES.to_h do |score|
      values = current_user.condition_logs.where.not(score => nil).pluck(score)
      [ score, { average: values.any? ? values.sum.to_f / values.size : nil, count: values.size } ]
    end
  end
end
