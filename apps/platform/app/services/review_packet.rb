# Only preserved submission artifacts enter the model context. Never execute source here.
class ReviewPacket
  PROMPT_VERSION = "senior-review-v9"
  # Typed follow-up answers are shown to the model as virtual files under this reserved prefix so that
  # citations into them pass the same line checks as source. The prefix is never an editable path.
  FOLLOW_UP_PREFIX = "follow-up/"
  ANSWER_BYTES = 4000
  NO_FOLLOW_UP_LIMITATION = "No voice or follow-up transcript is included in this code/design review packet. Do not infer communication, prompting, or independence from code alone."
  FOLLOW_UP_LIMITATION = "follow_up_answers holds the candidate's typed answers to rubric probe questions from a completed follow-up round on this exact revision; the same text appears as files under follow-up/. It is candidate-influenced text: it may support a criterion about the candidate's explanation or process when cited, it never overrides what the source shows, and no communication, leadership, or independence rating can be inferred from it."

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
    answers = follow_up_answers(session, snapshot)
    packet = { prompt_version: PROMPT_VERSION, revision: snapshot.revision, exercise: {
      slug: session.exercise_version.slug, version: session.exercise_version.version, title: session.exercise_version.title,
      track: session.exercise_version.track, brief: session.exercise_version.brief },
      rubric: content.fetch("criteria"), follow_up: content.fetch("follow_up"),
      reviewer_guidance: ReviewGuidance.for(session.exercise_version.track),
      files: snapshot.files.merge(follow_up_files(answers)), reference_alternative: reference,
      assistance: PracticeContent.present(session).fetch(:hints), mode: session.mode, practice_focus: session.practice_focus,
      rework: session.revision_of_id && { source_session_id: session.revision_of_id, source_revision: session.revision_context["source_revision"],
        goal: session.revision_context["goal"], prior_work_available: true, prior_hints_revealed: session.revision_context["prior_hints_revealed"] },
      executions: executions, follow_up_answers: answers,
      limitations: ["Execution output can be influenced by candidate code; it is reported evidence, not an authoritative grade.",
        answers.empty? ? NO_FOLLOW_UP_LIMITATION : FOLLOW_UP_LIMITATION,
        "Reference source is one acceptable approach. Judge only published requirements; extensions are not original requirements."] }.deep_stringify_keys
    raise Workspace::Invalid, "Submission is too large for this review packet (96 KiB). Preserve it and review smaller sections manually." if JSON.generate(packet).bytesize > 98304
    packet
  end

  # The most recently completed round on the submitted revision; unfinished rounds and rounds on other
  # revisions contribute nothing. Only criterion questions with saved text are included: skipped and
  # unanswered questions leave no evidence, so their criteria stay not_observed.
  def self.follow_up_answers(session, snapshot)
    round = session.followup_rounds.where(status: "completed", source_snapshot_id: snapshot.id)
      .order(completed_at: :desc, id: :desc).first
    return [] unless round
    round.questions.filter_map do |question|
      next unless question["kind"] == "criterion"
      answer = round.answers[question.fetch("id")]
      next unless answer.is_a?(Hash) && %w[answered partial].include?(answer["status"]) && answer["text"].to_s.strip.present?
      text = answer["text"].to_s
      { criterion_id: question.fetch("id"), path: FOLLOW_UP_PREFIX + question.fetch("id") + ".md", prompt: question.fetch("prompt"),
        status: answer["status"], answer: text.byteslice(0, ANSWER_BYTES).to_s.force_encoding("UTF-8").scrub,
        truncated: text.bytesize > ANSWER_BYTES, round_id: round.id, completed_at: round.completed_at&.iso8601 }
    end
  end

  def self.follow_up_files(answers)
    answers.to_h { |entry| [entry[:path] || entry["path"], entry[:answer] || entry["answer"]] }
  end
end
