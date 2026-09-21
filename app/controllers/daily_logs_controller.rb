class DailyLogsController < UserScopedController
  def show
    @daily_log = todays_log
  end

  def update
    saved = current_user.with_lock do
      @daily_log = todays_log
      @daily_log.assign_attributes(params.require(:daily_log).permit(
        :wakeup_freshness, :steps, :drank_alcohol,
        :sleep_hours, :sleep_remainder_minutes, :screen_hours, :screen_remainder_minutes
      ))
      @daily_log.save(context: :form)
    end

    if saved
      redirect_to user_daily_log_path(uuid: current_user.uuid), notice: "朝の記録を保存しました。", status: :see_other
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def todays_log
    current_user.daily_logs.find_by(date: Date.current) ||
      current_user.daily_logs.build(date: Date.current, wakeup_freshness: 5)
  end
end
