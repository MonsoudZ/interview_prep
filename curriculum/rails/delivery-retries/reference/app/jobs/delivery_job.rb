require "active_job"
class DeliveryJob < ActiveJob::Base
  class Retryable < StandardError; end
  def perform(delivery_id)
    delivery = Delivery.find_by(id: delivery_id)
    return unless delivery && delivery.status == "pending"
    unavailable = false
    code = begin
      DeliveryTransport.deliver(delivery)
    rescue DeliveryTransport::Unavailable
      unavailable = true
      nil
    end
    attempts = delivery.attempts + 1
    successful = !unavailable && code.between?(200, 299)
    permanent = !unavailable && code.between?(400, 499) && code != 429
    status = successful ? "delivered" : (permanent || attempts >= 3 ? "failed" : "pending")
    delivery.update!(attempts: attempts, last_http_status: code, status: status,
      last_error: successful ? nil : (unavailable ? "Transport unavailable" : "HTTP #{code}"))
    raise Retryable, "Delivery may be retried" if status == "pending"
  end
end
