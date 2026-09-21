# Run when the queue supervisor starts, not during Rails boot or a web request.
# bin/dev (embedded supervisor) and bin/jobs both use this hook.
SolidQueue.on_start do
  Rails.application.executor.wrap do
    WeatherSyncJob.perform_later
  end
end
