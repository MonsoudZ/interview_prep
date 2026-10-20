class BehavioralStory < ApplicationRecord
  belongs_to :account
  validates :title, presence: true, length: { maximum: 120 }
  validates :readiness, inclusion: { in: %w[draft ready] }
end
