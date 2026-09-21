class WeatherSample < ApplicationRecord
  belongs_to :location

  enum :data_kind, { realtime: 0, confirmed: 1 }, validate: true

  validates :observed_at, presence: true, uniqueness: { scope: [ :location_id, :data_kind ] }
  validates :pressure_msl, :temperature, :precipitation, numericality: true, allow_nil: true
  validates :humidity, :weather_code, numericality: { only_integer: true }, allow_nil: true
end
