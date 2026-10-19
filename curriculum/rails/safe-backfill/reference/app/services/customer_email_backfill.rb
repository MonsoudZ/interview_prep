class CustomerEmailBackfill
  def self.call(after_id:, through_id:, batch_size:)
    unless [after_id, through_id, batch_size].all? { |n| n.is_a?(Integer) } && after_id >= 0 && through_id >= after_id && batch_size.between?(1, 100)
      raise ArgumentError, "Invalid cursor or batch size"
    end
    rows = Customer.where("id > ? AND id <= ?", after_id, through_id).order(:id).limit(batch_size).to_a
    updated = conflicts = 0
    rows.each do |row|
      next unless row.normalized_email.nil?
      normalized = row.email&.strip&.downcase
      next if normalized.nil? || normalized.empty?
      begin
        # Compare both observed legacy data and the NULL migration state in SQL.
        updated += Customer.where(id: row.id, normalized_email: nil, email: row.email).update_all(normalized_email: normalized)
      rescue ActiveRecord::RecordNotUnique
        conflicts += 1
      end
    end
    cursor = rows.last&.id || after_id
    { cursor: cursor, scanned: rows.length, updated: updated, conflicts: conflicts,
      done: !Customer.where("id > ? AND id <= ?", cursor, through_id).exists? }
  end
end
