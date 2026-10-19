class SessionPresenter
  # Full runner output ships only for the newest execution and one explicitly selected
  # execution; older runs omit it so the 2.5 s workspace poll stays bounded.
  def self.call(session, with_output: nil)
    exercise = session.exercise_version
    { id: session.id, mode: session.mode, status: session.status, archived_at: session.archived_at, title: exercise.title, practice_focus: session.practice_focus,
      revision_of_id: session.revision_of_id, revision_context: session.revision_context,
      exercise_id: exercise.id, exercise_version: exercise.version, track: exercise.track,
      mock_interview_id: session.mock_interview_stage&.mock_interview_id,
      duration_minutes: session.mock_interview_stage ? session.mock_interview_stage.duration_seconds / 60 : exercise.duration_minutes, deadline_at: session.deadline_at,
      submitted_at: session.submitted_at, revision: session.current_revision,
      submitted_revision: session.submitted_revision, brief: exercise.brief,
      files: exercise.starter_files.merge(session.current_snapshot.files),
      initial_path: RailsCurriculum.initial_path(exercise),
      editable_paths: session.current_snapshot.files.keys, server_time: Time.current,
      executable: exercise.operation.present?, worker_available: exercise.operation.present? && WorkerNode.available?(exercise.operation),
      executions: session.execution_requests.order(created_at: :desc).limit(20).each_with_index.map { |execution, index|
        { id: execution.id, purpose: execution.purpose, status: execution.status,
          revision: execution.source_snapshot.revision, created_at: execution.created_at,
          result: result_for(execution, full: index.zero? || execution.id == with_output),
          reported_test_summary: ExecutionEvidence.summary(execution) }
      } }
  end

  def self.result_for(execution, full:)
    result = execution.result
    return result if full || result.nil?
    result.reject { |key, _| key.to_s == "output" }.merge("output_omitted" => true)
  end
end
