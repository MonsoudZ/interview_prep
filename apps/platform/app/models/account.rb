class Account < ApplicationRecord
  has_secure_password
  has_many :interview_sessions, dependent: :restrict_with_exception
  normalizes :email, with: ->(value) { value.strip.downcase }
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true, length: { maximum: 100 }
  validates :password, length: { minimum: 12, maximum: 72 }, if: -> { password.present? }
end
