class ReviewWorker < ApplicationRecord
  scope :available, -> { where("last_seen_at > ?", 45.seconds.ago) }
end
