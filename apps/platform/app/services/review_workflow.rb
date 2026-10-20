class ReviewWorkflow
  RATINGS = %w[not_observed needs_development approaching_target meets_target exceeds_target].freeze

  def self.validate!(entries, reflection, content, snapshot)
    raise Workspace::Invalid, "Expected review entries" unless entries.is_a?(Hash)
    criteria = content.fetch("criteria").map { |criterion| criterion.fetch("id") }
    raise Workspace::Invalid, "Unknown review criterion" unless (entries.keys - criteria).empty?
    raise Workspace::Invalid, "Reflection is too long" unless reflection.is_a?(String) && reflection.length <= 4000
    entries.each_value do |entry|
      raise Workspace::Invalid, "Invalid review entry" unless entry.is_a?(Hash) && (entry.keys - %w[rating notes evidence]).empty?
      raise Workspace::Invalid, "Invalid rating" unless RATINGS.include?(entry["rating"])
      raise Workspace::Invalid, "Add a concise explanation (maximum 2,000 characters)" unless entry["notes"].is_a?(String) && entry["notes"].length <= 2000
      evidence = entry["evidence"]
      if entry["rating"] != "not_observed" && (entry["notes"].blank? || evidence.blank?)
        raise Workspace::Invalid, "Each observed rating needs an explanation and a source reference"
      end
      next if evidence.nil?
      unless evidence.is_a?(Hash) && evidence.keys.sort == %w[end_line path start_line]
        raise Workspace::Invalid, "Invalid evidence reference"
      end
      if content["evidence_paths"] && !content["evidence_paths"].include?(evidence["path"])
        raise Workspace::Invalid, "Cite the rehearsed answer, not the preparation notes"
      end
      source = snapshot.files[evidence["path"]]
      first, last = evidence.values_at("start_line", "end_line")
      unless source && first.is_a?(Integer) && last.is_a?(Integer) && first >= 1 && last >= first && last <= source.lines.length && last - first < 20
        raise Workspace::Invalid, "Evidence must reference 1–20 existing lines in the submitted source"
      end
    end
  end

  def self.present(session, content)
    review = session.session_review
    snapshot = session.source_snapshots.find_by!(revision: session.submitted_revision)
    entries = (review&.entries || {}).transform_values do |entry|
      evidence = entry["evidence"]
      entry.merge("evidence" => evidence && evidence.merge("excerpt" => snapshot.files.fetch(evidence.fetch("path")).lines[(evidence.fetch("start_line") - 1)..(evidence.fetch("end_line") - 1)].join))
    end
    executions = session.execution_requests.joins(:source_snapshot)
      .where(source_snapshots: { revision: session.submitted_revision }, purpose: "tests").order(created_at: :desc).limit(10)
    gaps = content.fetch("criteria").filter_map do |criterion|
      entry = entries[criterion.fetch("id")]
      criterion.slice("id", "title", "practice") if entry && %w[needs_development approaching_target].include?(entry["rating"])
    end
    design = snapshot.files["diagram.json"] && DesignDocument.validate!(snapshot.files.fetch("diagram.json"))
    { preparation: session.behavioral_context, design: design, reference_available: RailsCurriculum.reference(session.exercise_version).present?, kind: "self_assessment", content_version: content.fetch("version"), revision: snapshot.revision,
      version: review&.lock_version, criteria: content.fetch("criteria"), ratings: RATINGS,
      entries: entries, reflection: review&.reflection || "", updated_at: review&.updated_at,
      evidence_files: snapshot.files.keys.sort & (content["evidence_paths"] || snapshot.files.keys), assistance: PracticeContent.present(session).fetch(:hints),
      next_steps: gaps, follow_up: content.fetch("follow_up"),
      executions: executions.map { |execution| { id: execution.id, status: execution.status, result: execution.result } } }
  end
end
