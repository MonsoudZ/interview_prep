class DeliveryTransport
  class Unavailable < StandardError; end
  def self.deliver(delivery)
    raise "Tests must stub transport; real network requests are outside this exercise"
  end
end
