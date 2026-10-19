class ExecutionRequest < ApplicationRecord
  belongs_to :interview_session
  belongs_to :source_snapshot
  validates :purpose, inclusion: { in: %w[prepare tests] }
  validates :status, inclusion: { in: %w[queued leased execution_completed execution_failed timed_out output_limit infrastructure_error] }
end
