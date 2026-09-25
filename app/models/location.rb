class Location < ApplicationRecord
  belongs_to :user
  has_many :weather_samples, dependent: :restrict_with_error

  after_create_commit :enqueue_weather_backfill

  validates :user_id, uniqueness: true
  validates :latitude, :longitude, numericality: true

  def weather_history_start
    registration_start = created_at.beginning_of_hour - 24.hours
    oldest_log = user.condition_logs.minimum(:recorded_at)
    log_start = oldest_log&.beginning_of_hour&.-(24.hours)
    [ registration_start, log_start ].compact.min
  end

  private

  def enqueue_weather_backfill
    WeatherBackfillJob.perform_later(location_id: id)
  end
end
