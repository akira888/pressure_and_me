class Location < ApplicationRecord
  belongs_to :user
  has_many :weather_samples, dependent: :restrict_with_error

  validates :user_id, uniqueness: true
  validates :latitude, :longitude, numericality: true
end
