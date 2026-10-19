class AutomatedReview < ApplicationRecord
  belongs_to :interview_session
  belongs_to :source_snapshot
  validates :status, inclusion: { in: %w[queued running completed failed] }
end
