require "date"
require "time"

class Event < ApplicationRecord
  validates :event_type, inclusion: { in: %w[push pull_request issue] }
  validate :integer_identifiers
  validate :explicit_timestamp

  def as_json(*)
    { id: id, event_type: event_type, actor_id: actor_id,
      repository_id: repository_id, occurred_at: occurred_at.utc.iso8601(3) }
  end

  private

  def integer_identifiers
    [:actor_id, :repository_id].each do |field|
      raw = public_send("#{field}_before_type_cast")
      errors.add(field, "must be a positive integer") unless raw.is_a?(Integer) && raw.positive?
    end
  end

  def explicit_timestamp
    raw = occurred_at_before_type_cast
    valid = raw.is_a?(String) && raw.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})\z/)
    DateTime.iso8601(raw) if valid
    errors.add(:occurred_at, "must be ISO 8601 with timezone") unless valid && occurred_at
  rescue ArgumentError
    errors.add(:occurred_at, "must be a valid timestamp")
  end
end
