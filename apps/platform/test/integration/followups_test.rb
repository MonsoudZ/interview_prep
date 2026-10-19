require "test_helper"

class FollowupsTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
    load Rails.root.join("db/seeds.rb")
    post "/api/register", params: { name: "Follow-up fixture", email: "followup@example.test", password: "followup-password-123" }, as: :json
    assert_response :ok
    @account = Account.find_by!(email: "followup@example.test")
  end
  def body = response.parsed_body
  def submission(track = "ruby", version = 2)
    exercise = ExerciseVersion.find_by!(track: track, version: version)
    record = @account.interview_sessions.create!(exercise_version: exercise, mode: "guided")
    Workspace.save!(record, exercise.starter_files.select { |path, _| Workspace.editable?(path, exercise) })
    record.update!(status: "submitted", submitted_revision: record.current_revision, submitted_at: Time.current)
    record
  end
  def create_round(session, **overrides)
    post "/api/sessions/#{session.id}/followups", params: { client_request_id: SecureRandom.uuid, mode: "guided" }.merge(overrides), as: :json
  end
  def command(round, kind, **overrides)
    round.reload
    patch "/api/followups/#{round.id}", params: { command: kind, expected_version: round.lock_version,
      question_index: round.question_index, answer: "Synthetic follow-up fixture; not the user's performance." }.merge(overrides), as: :json
  end
  def prepared(session = submission, **overrides)
    create_round(session, **overrides)
    assert_response :created
    FollowupRound.find(body.fetch("id"))
  end
  def started(session = submission, **overrides)
    round = prepared(session, **overrides)
    command(round, "start")
    assert_response :ok
    round.reload
  end

  test "each track snapshots its published questions while guidance stays hidden until completion" do
    [["rails", 1], ["ruby", 2], ["system_design", 2]].each do |track, version|
      session = submission(track, version)
      round = prepared(session)
      assert_equal session.submitted_revision, body["source_revision"]
      assert_nil body["question"]
      assert_nil body["transcript"]
      assert_nil round.started_at
      assert_nil round.deadline_at
      content = PracticeContent.for(session.exercise_version)
      assert_equal content["criteria"].length + 1, round.questions.length
      assert_equal round.questions.length * 120, round.duration_seconds
      command(round, "start")
      assert_response :ok
      assert_equal content["criteria"].first["probe"], body.dig("question", "prompt")
      refute body["question"].key?("target")
      refute body["question"].key?("practice")
      refute_includes response.body, content["follow_up"]
      command(round, "finish")
      assert_response :ok
      assert_equal content["criteria"].first["target"], body["transcript"].first["target"]
      assert_equal "extension", body["transcript"].last["kind"]
    end
  end

  test "creation is idempotent resumes an unfinished round and respects the account quota" do
    session = submission
    request_id = SecureRandom.uuid
    first = prepared(session, client_request_id: request_id)
    2.times do
      create_round(session, client_request_id: request_id)
      assert_response :ok
      assert_equal first.id, body["id"]
    end
    create_round(session, mode: "assessment")
    assert_response :ok
    assert_equal first.id, body["id"]
    assert_equal "guided", body["mode"]
    prepared(submission("system_design", 2))
    third = submission("rails", 1)
    create_round(third)
    assert_response :too_many_requests
    command(first, "start")
    command(first, "finish")
    create_round(session, client_request_id: request_id)
    assert_response :ok
    assert_equal first.id, body["id"]
    create_round(third)
    assert_response :created
  end

  test "autosave resumes exact text and stale writes cannot advance or overwrite another tab" do
    round = started
    old_version = round.lock_version
    command(round, "save", answer: "Saved reasoning <not HTML>.\nSecond line.")
    assert_response :ok
    get "/api/followups/#{round.id}"
    assert_response :ok
    assert_equal "Saved reasoning <not HTML>.\nSecond line.", body["current_draft"]
    command(round, "next", expected_version: old_version, answer: "Stale tab")
    assert_response :conflict
    assert_equal 0, round.reload.question_index
    assert_equal "Saved reasoning <not HTML>.\nSecond line.", round.current_draft
    command(round, "next", answer: round.current_draft)
    assert_response :ok
    assert_equal 1, body["question_index"]
    assert_equal "", body["current_draft"]
    command(round, "save", question_index: 0)
    assert_response :conflict
    assert_equal 1, round.reload.answers.length
  end

  test "answers lock on advance and explicit skips stay distinct in the finished transcript" do
    round = started
    command(round, "next", answer: " ")
    assert_response :unprocessable_content
    command(round, "skip", answer: "Partial idea retained with the skip.")
    assert_response :ok
    (round.questions.length - 1).times do
      command(round, "next")
      assert_response :ok
    end
    assert_equal "completed", body["status"]
    assert_equal "all_questions", body["completion_reason"]
    assert_equal "skipped", body["transcript"].first.dig("answer", "status")
    assert_equal "Partial idea retained with the skip.", body["transcript"].first.dig("answer", "text")
    assert_equal "answered", body["transcript"].last.dig("answer", "status")
    frozen = round.reload.answers.deep_dup
    command(round, "save", answer: "Cannot replace the finished transcript")
    assert_response :conflict
    assert_equal frozen, round.reload.answers
  end

  test "timed deadlines persist the last saved partial answer and reject late edits even on stale writes" do
    round = prepared
    command(round, "start", mode: "assessment")
    assert_response :ok
    assert_equal "assessment", body["mode"]
    assert round.reload.deadline_at
    command(round, "save", answer: "Accepted before the deadline.")
    version = round.reload.lock_version
    deadline = round.deadline_at
    travel_to deadline + 2.seconds do
      command(round, "save", expected_version: version, answer: "Late text must not replace the saved answer.")
      assert_response :conflict
      assert_equal "completed", round.reload.status
      assert_equal "deadline", round.completion_reason
      assert_equal deadline, round.completed_at
      assert_equal "Accepted before the deadline.", round.answers.fetch(round.questions.first["id"]).fetch("text")
      get "/api/followups/#{round.id}"
      assert_response :ok
      assert_equal "partial", body["transcript"].first.dig("answer", "status")
      assert_equal "unanswered", body["transcript"].last.dig("answer", "status")
    end
  end

  test "guided rounds have no deadline and early finish preserves partial and unasked responses" do
    round = started
    assert_nil round.deadline_at
    command(round, "finish", answer: "An unfinished explanation.")
    assert_response :ok
    assert_equal "finished_early", body["completion_reason"]
    assert_equal "partial", body["transcript"].first.dig("answer", "status")
    assert_equal "An unfinished explanation.", body["transcript"].first.dig("answer", "text")
    assert body["transcript"].drop(1).all? { |item| item.dig("answer", "status") == "unanswered" }
  end

  test "completed self-checks require reasons cannot claim skipped answers and leave source progress untouched" do
    session = submission
    round = started(session)
    question = round.questions.first["id"]
    command(round, "next", answer: "An actual typed fixture explanation.")
    command(round, "finish", answer: "")
    answers = round.reload.answers.deep_dup
    command(round, "review", review_entries: { question => { rating: "explained", note: "I named the invariant and a counterexample." } }, reflection: "Rehearse without looking next time.")
    assert_response :ok
    assert_equal "explained", body.dig("review_entries", question, "rating")
    assert_equal answers, round.reload.answers
    stale = round.lock_version
    command(round, "review", review_entries: {}, reflection: "New reflection")
    assert_response :ok
    command(round, "review", expected_version: stale, review_entries: {}, reflection: "Stale reflection")
    assert_response :conflict
    assert_equal "New reflection", round.reload.reflection
    unanswered = round.questions.last["id"]
    command(round, "review", review_entries: { unanswered => { rating: "explained", note: "Invented claim" } }, reflection: "")
    assert_response :unprocessable_content
    command(round, "review", review_entries: { question => { rating: "needs_practice", note: "" } }, reflection: "")
    assert_response :unprocessable_content
    assert_nil session.reload.session_review
    get "/api/progress"
    assert_response :ok
    assert_empty body["skills"]
    assert_equal 1, body.dig("summary", "submitted")
    summary = body.fetch("followups").first
    assert_equal round.id, summary["id"]
    assert_equal session.id, summary["session_id"]
    assert_equal "completed", summary["status"]
    refute summary.key?("answers")
    refute summary.key?("transcript")
  end

  test "invalid commands and payloads cannot change question state or transcript" do
    session = submission
    create_round(session, client_request_id: "bad")
    assert_response :unprocessable_content
    create_round(session, mode: "unknown")
    assert_response :unprocessable_content
    round = started(session)
    command(round, "save", answer: "x" * 8001)
    assert_response :unprocessable_content
    command(round, "save", answer: { injected: "not text" })
    assert_response :unprocessable_content
    command(round, "unknown")
    assert_response :unprocessable_content
    command(round, "save", question_index: 0.0)
    assert_response :conflict
    command(round, "review", review_entries: {}, reflection: "premature")
    assert_response :conflict
    assert_empty round.reload.answers
    assert_equal "", round.current_draft
  end

  test "only submitted owned sessions and owned rounds are available" do
    session = submission
    round = started(session)
    draft = @account.interview_sessions.create!(exercise_version: session.exercise_version, mode: "guided")
    create_round(draft)
    assert_response :conflict
    get "/api/sessions/#{draft.id}/followups"
    assert_response :conflict
    delete "/api/logout", as: :json
    get "/api/followups/#{round.id}"
    assert_response :unauthorized
    post "/api/register", params: { name: "Other", email: "other-followup@example.test", password: "other-followup-password-123" }, as: :json
    get "/api/sessions/#{session.id}/followups"
    assert_response :not_found
    create_round(session)
    assert_response :not_found
    get "/api/followups/#{round.id}"
    assert_response :not_found
    command(round, "save")
    assert_response :not_found
    get "/api/progress"
    assert_response :ok
    assert_empty body["followups"]
    refute_includes response.body, round.id
  end
end
