class SessionPresenter
  def self.call(session)
    exercise = session.exercise_version
    { id: session.id, mode: session.mode, status: session.status, title: exercise.title, practice_focus: session.practice_focus,
      revision_of_id: session.revision_of_id, revision_context: session.revision_context,
      exercise_id: exercise.id, exercise_version: exercise.version, track: exercise.track,
      duration_minutes: exercise.duration_minutes, deadline_at: session.deadline_at,
      submitted_at: session.submitted_at, revision: session.current_revision,
      submitted_revision: session.submitted_revision, brief: exercise.brief,
      files: exercise.starter_files.merge(session.current_snapshot.files),
      editable_paths: session.current_snapshot.files.keys, server_time: Time.current,
      executable: exercise.operation.present?, worker_available: exercise.operation.present? && WorkerNode.available?(exercise.operation),
      executions: session.execution_requests.order(created_at: :desc).limit(20).map { |execution|
        { id: execution.id, purpose: execution.purpose, status: execution.status,
          revision: execution.source_snapshot.revision, created_at: execution.created_at, result: execution.result,
          reported_test_summary: ExecutionEvidence.summary(execution) }
      } }
  end
end
