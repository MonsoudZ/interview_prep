class FollowupRound < ApplicationRecord
  belongs_to :interview_session
  belongs_to :source_snapshot
  validates :mode, inclusion: { in: %w[guided assessment] }
  validates :status, inclusion: { in: %w[ready active completed] }

  def expire_locked!
    complete_locked!("deadline") if status == "active" && deadline_at && deadline_at <= Time.current
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
