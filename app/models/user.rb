class User < ApplicationRecord
  has_one :location, dependent: :restrict_with_error
  has_many :condition_logs, dependent: :restrict_with_error
  has_many :daily_logs, dependent: :restrict_with_error
end
