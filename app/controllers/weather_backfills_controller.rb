class WeatherBackfillsController < UserScopedController
  def create
    location = current_user.location
    if location
      WeatherBackfillJob.perform_later(location_id: location.id)
      redirect_to user_analysis_path(uuid: current_user.uuid), status: :see_other,
        notice: "過去の気象データの再取得を予約しました。反映まで時間がかかるため、しばらくしてからページを再読み込みしてください。"
    else
      redirect_to user_analysis_path(uuid: current_user.uuid), status: :see_other,
        alert: "地点が未登録のため、気象データを再取得できません。"
    end
  end
end
