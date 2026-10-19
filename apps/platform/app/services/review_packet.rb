# Only preserved submission artifacts enter the model context. Never execute source here.
class ReviewPacket
  PROMPT_VERSION = "senior-review-v1"
  def self.build(session)
    content = PracticeContent.for(session.exercise_version)
    raise Workspace::Invalid, "No review rubric for this version" unless content
    snapshot = session.source_snapshots.find_by!(revision: session.submitted_revision)
    executions = session.execution_requests.joins(:source_snapshot).where(purpose: "tests",
      source_snapshots: { revision: snapshot.revision }).order(created_at: :desc).limit(3).map do |run|
      { id: run.id, status: run.status, reported_summary: ExecutionEvidence.summary(run),
        output: run.result&.fetch("output", "").to_s.byteslice(0, 12000).to_s.force_encoding("UTF-8").scrub,
        output_truncated: run.result&.fetch("output_truncated", false) || run.result&.fetch("output", "").to_s.bytesize > 12000 }
    end
    reference = RailsCurriculum.reference(session.exercise_version)
    packet = { prompt_version: PROMPT_VERSION, revision: snapshot.revision, exercise: {
      slug: session.exercise_version.slug, version: session.exercise_version.version, title: session.exercise_version.title,
      track: session.exercise_version.track, brief: session.exercise_version.brief },
      rubric: content.fetch("criteria"), follow_up: content.fetch("follow_up"),
      files: snapshot.files, reference_alternative: reference,
      assistance: PracticeContent.present(session).fetch(:hints), mode: session.mode, practice_focus: session.practice_focus,
      rework: session.revision_of_id && { source_session_id: session.revision_of_id, source_revision: session.revision_context["source_revision"],
        goal: session.revision_context["goal"], prior_work_available: true, prior_hints_revealed: session.revision_context["prior_hints_revealed"] },
      executions: executions, limitations: ["Execution output can be influenced by candidate code; it is reported evidence, not an authoritative grade.",
        "No voice or follow-up transcript is included in this code/design review packet. Do not infer communication, prompting, or independence from code alone.",
        "Reference source is one acceptable approach. Judge only published requirements; extensions are not original requirements."] }.deep_stringify_keys
    raise Workspace::Invalid, "Submission is too large for this review packet (96 KiB). Preserve it and review smaller sections manually." if JSON.generate(packet).bytesize > 98304
    packet
  end
end
