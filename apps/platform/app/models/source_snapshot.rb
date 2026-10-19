class SourceSnapshot < ApplicationRecord
  belongs_to :interview_session
  validates :revision, presence: true, uniqueness: { scope: :interview_session_id }
  def readonly?
    persisted?
  end
end
