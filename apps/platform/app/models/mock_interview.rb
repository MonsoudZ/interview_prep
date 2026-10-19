class MockInterview < ApplicationRecord
  belongs_to :account
  has_many :mock_interview_stages, -> { order(:position) }
  validates :status, inclusion: { in: %w[ready active completed] }
end
