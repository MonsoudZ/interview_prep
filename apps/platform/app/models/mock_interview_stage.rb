class MockInterviewStage < ApplicationRecord
  belongs_to :mock_interview
  belongs_to :exercise_version, optional: true
  belongs_to :interview_session, optional: true
  belongs_to :followup_round, optional: true
end
