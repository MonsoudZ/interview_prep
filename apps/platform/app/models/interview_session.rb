class InterviewSession < ApplicationRecord
  belongs_to :account
  belongs_to :exercise_version
  belongs_to :revision_of, class_name: "InterviewSession", optional: true
  has_many :reworks, class_name: "InterviewSession", foreign_key: :revision_of_id
  has_many :source_snapshots
  has_many :execution_requests
  has_many :hint_reveals
  has_many :automated_reviews
  has_many :followup_rounds
  has_one :session_review
  validates :mode, inclusion: { in: %w[guided assessment] }
  validates :status, inclusion: { in: %w[draft preparing ready active submitted] }

  def expire!
    with_lock { expire_locked! }
  end

  # Call only while holding this session's database lock, including immediately before writes.
  def expire_locked!
    if status == "active" && deadline_at && deadline_at <= Time.current
      update!(status: "submitted", submitted_revision: current_revision, submitted_at: deadline_at)
    end
  end

  def current_snapshot
    source_snapshots.find_by!(revision: current_revision)
  end
end
