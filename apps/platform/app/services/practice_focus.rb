class PracticeFocus
  # Derive the drill from an owned, reviewed submission; never accept client-authored instructions.
  def self.build!(account, exercise, value)
    return nil if value.nil?
    unless value.is_a?(Hash) && value.keys.sort == %w[criterion_id source_session_id] &&
        value["source_session_id"].is_a?(String) && value["source_session_id"].match?(/\A[0-9a-f-]{36}\z/) &&
        value["criterion_id"].is_a?(String) && value["criterion_id"].match?(/\A[a-z_]{1,80}\z/)
      raise Workspace::Invalid, "Invalid practice focus"
    end
    source = account.interview_sessions.find(value.fetch("source_session_id"))
    content = PracticeContent.for(source.exercise_version)
    criterion = content&.fetch("criteria")&.find { |item| item.fetch("id") == value["criterion_id"] }
    rating = source.session_review&.entries&.dig(value["criterion_id"], "rating")
    unless source.status == "submitted" && source.exercise_version.slug == exercise.slug && criterion && ProgressOverview::GAPS.include?(rating)
      raise Workspace::Invalid, "This practice focus changed. Refresh Progress before starting another attempt."
    end
    active = ProgressOverview.call(account).fetch(:plan).any? do |item|
      item[:latest][:session_id] == source.id && item[:criterion_id] == criterion.fetch("id") && item[:content_version] == content.fetch("version")
    end
    raise Workspace::Invalid, "This practice focus changed. Refresh Progress before starting another attempt." unless active
    { "source_session_id" => source.id, "source_revision" => source.submitted_revision,
      "content_version" => content.fetch("version"), "criterion_id" => criterion.fetch("id"),
      "title" => criterion.fetch("title"), "practice" => criterion.fetch("practice") }
  end
end
