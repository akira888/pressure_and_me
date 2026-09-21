module DomainRecords
  def domain_user
    @domain_user ||= User.create!
  end

  def domain_location
    @domain_location ||= Location.create!(user: domain_user, latitude: "35.681236", longitude: "139.767125")
  end

  def build_record(model, **overrides)
    attributes = case model.name
    when "Location"
      { user: domain_user, latitude: "35.681236", longitude: "139.767125" }
    when "WeatherSample"
      { location: domain_location, observed_at: Time.zone.local(2026, 9, 21, 10), data_kind: :realtime,
        pressure_msl: "1013.25", temperature: "25.125", humidity: 60, precipitation: "0.125", weather_code: 3 }
    when "ConditionLog"
      { user: domain_user, recorded_at: Time.zone.local(2026, 9, 21, 10, 37),
        headache: 1, nausea: 2, fatigue: 3, appetite: 9, clarity: 10 }
    when "DailyLog"
      { user: domain_user, date: Date.new(2026, 9, 21), wakeup_freshness: 5,
        sleep_minutes: 450, steps: 3000, drank_alcohol: false, screen_minutes: 120 }
    end
    model.new(attributes.merge(overrides))
  end
end
