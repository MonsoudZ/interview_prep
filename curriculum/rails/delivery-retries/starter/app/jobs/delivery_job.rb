require "active_job"
class DeliveryJob < ActiveJob::Base
  class Retryable < StandardError; end
  def perform(delivery_id)
    # Implement the published state transitions.
  end
end
