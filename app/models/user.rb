class User < ApplicationRecord
  attribute :uuid, :string, default: -> { SecureRandom.uuid }

  has_one :location, dependent: :restrict_with_error
  has_many :condition_logs, dependent: :restrict_with_error
  has_many :daily_logs, dependent: :restrict_with_error

  validates :uuid, presence: true, uniqueness: true,
    format: { with: /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/ }
end
