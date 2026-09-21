class Location < ApplicationRecord
  belongs_to :user
  has_many :weather_samples, dependent: :restrict_with_error

  after_create_commit :enqueue_weather_backfill

  validates :user_id, uniqueness: true
  validates :latitude, :longitude, numericality: true

  def weather_history_start
    created_at.beginning_of_hour - 24.hours
  end

  private

  def enqueue_weather_backfill
    WeatherBackfillJob.perform_later(location_id: id)
  end
end
