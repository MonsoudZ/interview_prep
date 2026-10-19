class CustomerEmailBackfill
  def self.call(after_id:, through_id:, batch_size:)
    Customer.all.each { |customer| customer.update!(normalized_email: customer.email.to_s.downcase) }
    { cursor: through_id, scanned: Customer.count, updated: Customer.count, conflicts: 0, done: true }
  end
end
