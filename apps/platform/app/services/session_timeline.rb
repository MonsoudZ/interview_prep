# Replays the owner's own saved revisions in order. Only preserved snapshots, recorded
# executions and hint reveals are read; nothing is executed, graded or inferred.
class SessionTimeline
  def self.call(session, revision: nil)
    exercise = session.exercise_version
    snapshots = session.source_snapshots.order(:created_at, :id).to_a
    runs = session.execution_requests.includes(:source_snapshot).order(:created_at, :id).to_a
      .group_by { |run| run.source_snapshot.revision }
    hints = session.hint_reveals.order(:created_at, :id).to_a
    origin = snapshots.first&.created_at
    steps = snapshots.each_with_index.map do |snapshot, index|
      previous = previous_files(snapshots, index, exercise)
      next_at = snapshots[index + 1]&.created_at
      { revision: snapshot.revision, created_at: snapshot.created_at,
        offset_seconds: (snapshot.created_at - origin).round,
        changed_paths: (previous.keys | snapshot.files.keys).sort.select { |path| previous[path] != snapshot.files[path] },
        executions: (runs[snapshot.revision] || []).map { |run|
          { id: run.id, purpose: run.purpose, status: run.status, created_at: run.created_at,
            summary: ExecutionEvidence.summary(run, exercise: exercise) } },
        hints: hints.select { |hint| hint.created_at >= snapshot.created_at && (next_at.nil? || hint.created_at < next_at) }.map(&:position),
        submitted: snapshot.revision == session.submitted_revision }
    end
    selected = revision && snapshots.index { |snapshot| snapshot.revision == revision }
    raise ActiveRecord::RecordNotFound if revision && selected.nil?
    { session_id: session.id, status: session.status, started_at: session.started_at, submitted_at: session.submitted_at,
      submitted_revision: session.submitted_revision, steps: steps,
      changes: selected && changes(previous_files(snapshots, selected, exercise), snapshots[selected].files),
      note: "Saved revisions only. Time between saves is not a measure of thinking or typing, and replaying your own attempt does not evaluate it." }
  end

  def self.previous_files(snapshots, index, exercise)
    return snapshots[index - 1].files if index.positive?
    exercise.starter_files.select { |path, _| Workspace.editable?(path, exercise) }
  end

  def self.changes(before, after)
    (before.keys | after.keys).sort.filter_map do |path|
      next if before[path] == after[path]
      { path: path, before: before[path], after: after[path],
        kind: before[path].nil? ? "added" : after[path].nil? ? "removed" : "modified" }
    end
  end
end
