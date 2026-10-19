class SessionReview < ApplicationRecord
  belongs_to :interview_session
  belongs_to :source_snapshot
end
