class FollowupRound < ApplicationRecord
  has_one :mock_interview_stage
  belongs_to :interview_session
  belongs_to :source_snapshot
  validates :mode, inclusion: { in: %w[guided assessment] }
  validates :status, inclusion: { in: %w[ready active completed] }

  def expire_locked!
    overall_deadline = mock_interview_stage&.mock_interview&.deadline_at
    if status != "completed" && overall_deadline && overall_deadline <= Time.current
      update!(deadline_at: overall_deadline)
      complete_locked!("deadline")
    elsif status == "active" && deadline_at && deadline_at <= Time.current
      complete_locked!("deadline")
    end
  end

  def complete_locked!(reason)
    saved = answers.deep_dup
    question = questions[question_index]
    if question && current_draft.present?
      saved[question.fetch("id")] = { "text" => current_draft, "status" => "partial", "saved_at" => Time.current.iso8601 }
    end
    update!(status: "completed", answers: saved, current_draft: "", completion_reason: reason,
      completed_at: reason == "deadline" ? deadline_at : Time.current)
  end
end
