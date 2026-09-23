class AnalysesController < UserScopedController
  def show
    @condition_logs = current_user.condition_logs.order(recorded_at: :desc).limit(20)
    @weather_metrics = @condition_logs.to_h { |log| [ log.id, log.weather_metrics ] }
  end
end
