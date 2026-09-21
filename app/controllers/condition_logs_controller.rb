class ConditionLogsController < UserScopedController
  def new
    previous = current_user.condition_logs.order(recorded_at: :desc, id: :desc).first
    scores = ConditionLog::SCORES.index_with { |score| previous ? previous.public_send(score) : 5 }
    @condition_log = current_user.condition_logs.build(scores.merge(recorded_at: Time.current))
  end

  def create
    @condition_log = current_user.condition_logs.build(
      params.require(:condition_log).permit(:recorded_at, *ConditionLog::SCORES)
    )
    if @condition_log.save
      redirect_to user_home_path(uuid: current_user.uuid), notice: "体調を記録しました。", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end
end
