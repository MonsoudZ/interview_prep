class WorkerNode < ApplicationRecord
  def self.available?(operation)
    where("last_seen_at > ?", 45.seconds.ago).any? { |worker| worker.capabilities.include?(operation) }
  end
end
