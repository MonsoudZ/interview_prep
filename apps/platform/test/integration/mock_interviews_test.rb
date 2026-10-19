require "test_helper"
class MockInterviewsTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
    load Rails.root.join("db/seeds.rb")
    post "/api/register", params: { name: "Mock fixture", email: "mock@example.test", password: "mock-fixture-password-123" }, as: :json
    assert_response :ok
    @account = Account.find_by!(email: "mock@example.test")
  end
  def body = response.parsed_body
  def book(plan = "debugging", request_id = SecureRandom.uuid)
    post "/api/mock_interviews", params: { plan_key: plan, client_request_id: request_id }, as: :json
    assert_response :created
    MockInterview.find(body.fetch("id"))
  end
  def command(mock, kind, **extra)
    mock.reload
    patch "/api/mock_interviews/#{mock.id}", params: { command: kind, expected_version: mock.lock_version }.merge(extra), as: :json
  end
  def start_stage(mock)
    record = mock.mock_interview_stages.find_by!(position: mock.reload.stage_index).interview_session
    if record.exercise_version.operation
      record.update!(status: "ready")
      WorkerNode.create!(capabilities: [record.exercise_version.operation], last_seen_at: Time.current)
    end
    post "/api/sessions/#{record.id}/start", as: :json
    assert_response :ok
    record.reload
  end
  def submit_stage(mock)
    record = start_stage(mock)
    post "/api/sessions/#{record.id}/submit", params: { expected_revision: record.current_revision }, as: :json
    assert_response :ok
    record.reload
  end
  def followup_stage(mock)
    2.times do
      submit_stage(mock)
      command(mock, "advance"); assert_response :ok
    end
    mock.mock_interview_stages.find_by!(position: 2).followup_round
  end
  def follow_command(round, kind, **extra)
    round.reload
    patch "/api/followups/#{round.id}", params: { command: kind, expected_version: round.lock_version,
      question_index: round.question_index, answer: "Synthetic interview verification; not personal performance." }.merge(extra), as: :json
  end
  test "booking pins schedules versions and only the first workspace" do
    get "/api/mock_interviews"; assert_response :ok
    assert_equal [149, 89, 114], body.fetch("plans").map { |p| p["duration_minutes"] }
    mock = book("senior-backend")
    assert_equal 4, body.fetch("stages").length
    assert_nil body["deadline_at"]
    assert_equal [1, 2, 2, nil], body.fetch("stages").map { |s| s["exercise_version"] }
    assert_equal [3600, 2100, 2400, 840], body.fetch("stages").map { |s| s["duration_seconds"] }
    assert_equal 1, mock.mock_interview_stages.where.not(interview_session_id: nil).count
    assert body.fetch("stages").drop(1).all? { |s| s["session_id"].nil? && s["followup_id"].nil? }
    assert_equal "assessment", mock.mock_interview_stages.first.interview_session.mode
  end
  test "retry identity and unfinished interview quota" do
    request_id = SecureRandom.uuid
    first = book("debugging", request_id)
    assert_equal first.id, book("debugging", request_id).id
    book("migration")
    post "/api/mock_interviews", params: { plan_key: "senior-backend", client_request_id: SecureRandom.uuid }, as: :json
    assert_response :too_many_requests
    command(first, "finish"); assert_response :ok
    book("senior-backend")
    post "/api/mock_interviews", params: { plan_key: "unknown", client_request_id: SecureRandom.uuid }, as: :json
    assert_response :unprocessable_content
    post "/api/mock_interviews", params: { plan_key: "debugging", client_request_id: "bad" }, as: :json
    assert_response :unprocessable_content
  end
  test "clock waits for readiness then uses captured stage budget" do
    mock = book
    session = mock.mock_interview_stages.first.interview_session
    post "/api/sessions/#{session.id}/start", as: :json
    assert_response :conflict
    assert_nil mock.reload.started_at; assert_nil mock.deadline_at
    travel_to Time.current.change(usec: 0) do
      session = start_stage(mock)
      assert_equal 40.minutes.from_now, session.deadline_at
      assert_equal 89.minutes.from_now, mock.reload.deadline_at
      assert_equal "active", mock.status
      assert_equal 55, session.exercise_version.duration_minutes
      get "/api/sessions/#{session.id}"; assert_response :ok
      assert_equal 40, body["duration_minutes"]; assert_equal mock.id, body["mock_interview_id"]
    end
  end
  test "advance requires completion rejects stale tabs and preserves source" do
    mock = book
    command(mock, "advance"); assert_response :conflict
    first = submit_stage(mock); revision = first.submitted_revision; version = mock.reload.lock_version
    command(mock, "advance"); assert_response :ok
    assert_equal 1, body["stage_index"]
    assert_equal "webhook-delivery", mock.mock_interview_stages.find_by!(position: 1).exercise_version.slug
    command(mock, "advance", expected_version: version); assert_response :conflict
    assert_equal 1, mock.reload.stage_index
    assert_equal revision, first.reload.submitted_revision
    assert_equal 2, mock.mock_interview_stages.where.not(interview_session_id: nil).count
  end
  test "overall deadline includes transitions and clamps later stages" do
    mock = book
    first = submit_stage(mock)
    command(mock, "advance"); assert_response :ok
    deadline = mock.reload.deadline_at
    travel_to deadline - 2.minutes do
      design = start_stage(mock)
      assert_equal deadline, design.deadline_at
    end
    travel_to deadline + 1.second do
      get "/api/mock_interviews/#{mock.id}"; assert_response :ok
      assert_equal "completed", body["status"]; assert_equal "deadline", body["completion_reason"]
      assert_equal "unattempted", body.fetch("stages").last["status"]
      assert_equal "submitted", mock.mock_interview_stages.find_by!(position: 1).interview_session.status
      assert_equal first.submitted_revision, first.reload.submitted_revision
      assert_equal deadline, mock.reload.completed_at
    end
  end
  test "stage expiry freezes work while overall interview remains active" do
    mock = book; session = start_stage(mock)
    travel_to session.deadline_at + 1.second do
      get "/api/mock_interviews/#{mock.id}"; assert_response :ok
      assert_equal "active", body["status"]; assert_equal "submitted", session.reload.status
      command(mock, "advance"); assert_response :ok
      assert_equal 1, body["stage_index"]
    end
  end
  test "late writes to an unstarted stage cannot bypass the overall deadline" do
    mock = book
    submit_stage(mock); command(mock, "advance"); assert_response :ok
    design = mock.mock_interview_stages.find_by!(position: 1).interview_session
    revision = design.current_revision
    files = design.current_snapshot.files.merge("notes.md" => "Late work must not be submitted")
    travel_to mock.reload.deadline_at + 1.second do
      put "/api/sessions/#{design.id}/snapshot", params: { expected_revision: revision, files: files }, as: :json
      assert_response :conflict
      assert_equal "submitted", design.reload.status; assert_equal revision, design.submitted_revision
      command(mock, "advance"); assert_response :conflict
      assert_equal "completed", mock.reload.status
    end
  end
  test "followups capture multiple submitted sources and enforce assessment mode" do
    mock = book; round = followup_stage(mock)
    assert_equal 7, round.questions.length
    sources = mock.mock_interview_stages.where(kind: "workspace").map(&:interview_session)
    assert_equal sources.map(&:id).sort, round.questions.map { |q| q.fetch("source_session_id") }.uniq.sort
    sources.each { |source| assert round.questions.any? { |q| q["source_session_id"] == source.id && q["source_revision"] == source.submitted_revision } }
    follow_command(round, "start", mode: "guided"); assert_response :conflict
    follow_command(round, "start"); assert_response :ok
    assert_equal "assessment", body["mode"]; assert_nil body["transcript"]; assert_equal mock.id, body["mock_interview_id"]
    assert_operator round.reload.deadline_at, :<=, mock.reload.deadline_at
    follow_command(round, "finish", answer: "Partial explanation"); assert_response :ok
    command(mock, "advance"); assert_response :ok
    assert_equal "completed", body["status"]; assert_equal "all_stages", body["completion_reason"]
    assert_equal "partial", body.fetch("stages").last.dig("transcript", "transcript", 0, "answer", "status")
  end
  test "early finish freezes saved draft and keeps unopened stages unattempted" do
    mock = book; session = start_stage(mock)
    Workspace.save!(session, session.current_snapshot.files.merge("app/models/fixture_note.rb" => "# Synthetic verification work\n"))
    command(mock, "finish"); assert_response :ok
    assert_equal "completed", body["status"]; assert_equal "finished_early", body["completion_reason"]
    assert_equal "submitted", session.reload.status; assert_equal session.current_revision, session.submitted_revision
    assert body.fetch("stages").drop(1).all? { |s| s["status"] == "unattempted" }
    command(mock, "advance"); assert_response :conflict
    command(mock, "reflect", reflection: "Synthetic overall reflection."); assert_response :ok
    assert_equal "Synthetic overall reflection.", body["reflection"]
    command(mock, "reflect", reflection: "x" * 4001); assert_response :unprocessable_content
  end
  test "review includes only same revision tests with self assessments separate" do
    mock = book; session = submit_stage(mock); submitted = session.current_snapshot
    session.execution_requests.create!(source_snapshot: submitted, client_request_id: SecureRandom.uuid, purpose: "tests", status: "execution_failed", result: { output: "12 runs, 20 assertions, 3 failures, 0 errors, 0 skips" })
    old = session.source_snapshots.create!(revision: "a" * 64, files: { "app/models/old.rb" => "# Earlier source" })
    session.execution_requests.create!(source_snapshot: old, client_request_id: SecureRandom.uuid, purpose: "tests", status: "execution_completed", result: { output: "12 runs, 20 assertions, 0 failures, 0 errors, 0 skips" })
    command(mock, "finish"); assert_response :ok
    evidence = body.fetch("stages").first.fetch("evidence")
    assert_equal submitted.revision, evidence["revision"]; assert_equal 1, evidence["reported_tests"].length
    assert_equal 9, evidence["reported_tests"].first.dig("summary", "passed")
    assert_empty evidence["self_assessment"]; assert_equal "evidence_summary", body["review_kind"]; refute body.key?("score")
  end
  test "senior loop includes Ruby and questions from all three sources" do
    mock = book("senior-backend")
    %w[invoice-amendments merge-intervals webhook-delivery].each do |slug|
      assert_equal slug, mock.mock_interview_stages.find_by!(position: mock.reload.stage_index).exercise_version.slug
      submit_stage(mock); command(mock, "advance"); assert_response :ok
    end
    round = mock.mock_interview_stages.last.followup_round
    assert_equal 7, round.questions.length; assert_equal 3, round.questions.map { |q| q["source_session_id"] }.uniq.length
  end
  test "interview and child access are owner scoped" do
    mock = book; child = mock.mock_interview_stages.first.interview_session
    delete "/api/logout", as: :json
    get "/api/mock_interviews/#{mock.id}"; assert_response :unauthorized
    post "/api/register", params: { name: "Other", email: "other-mock@example.test", password: "other-mock-password-123" }, as: :json
    get "/api/mock_interviews/#{mock.id}"; assert_response :not_found
    command(mock, "finish"); assert_response :not_found
    get "/api/sessions/#{child.id}"; assert_response :not_found
    get "/api/mock_interviews"; assert_response :ok; assert_empty body["interviews"]
  end
  test "saved stage gaps populate interview practice without changing standalone trends" do
    mock = book
    session = submit_stage(mock)
    command(mock, "finish"); assert_response :ok
    criterion = PracticeContent.for(session.exercise_version).fetch("criteria").first
    put "/api/sessions/#{session.id}/review", params: { expected_version: nil, entries: {
      criterion.fetch("id") => { rating: "needs_development", notes: "Synthetic verification gap, not personal performance.",
        evidence: { path: "app/controllers/escalations_controller.rb", start_line: 1, end_line: 3 } }
    }, reflection: "Synthetic review fixture" }, as: :json
    assert_response :ok
    get "/api/mock_interviews/#{mock.id}"; assert_response :ok
    assert_equal criterion.fetch("practice"), body.fetch("next_steps").first.fetch("practice")
    get "/api/progress"; assert_response :ok
    assert_empty body["skills"]
    assert_equal mock.id, body.fetch("recent_attempts").first.fetch("mock_interview_id")
  end

  test "overall expiry preserves saved followup drafts and rejects late mode or answer changes" do
    mock = book
    round = followup_stage(mock)
    follow_command(round, "start"); assert_response :ok
    follow_command(round, "save", answer: "Accepted synthetic draft."); assert_response :ok
    mock.reload.update!(deadline_at: 1.second.ago)
    follow_command(round, "save", answer: "Late replacement"); assert_response :conflict
    assert_equal "completed", round.reload.status
    assert_equal "Accepted synthetic draft.", round.answers.fetch(round.questions.first.fetch("id")).fetch("text")
    get "/api/mock_interviews/#{mock.id}"; assert_response :ok
    assert_equal "deadline", body["completion_reason"]
  end

  test "mock source and test runs stay locked until the stage timer starts" do
    mock = book
    child = mock.mock_interview_stages.first.interview_session
    put "/api/sessions/#{child.id}/snapshot", params: { expected_revision: child.current_revision, files: child.current_snapshot.files }, as: :json
    assert_response :conflict
    post "/api/sessions/#{child.id}/execute", params: { client_request_id: SecureRandom.uuid }, as: :json
    assert_response :conflict
    assert_empty child.execution_requests
    assert_nil mock.reload.started_at
    get "/api/sessions"; assert_response :ok
    assert_equal mock.id, body.fetch("sessions").find { |item| item["id"] == child.id }.fetch("mock_interview_id")
    start_stage(mock)
    put "/api/sessions/#{child.id}/snapshot", params: { expected_revision: child.current_revision, files: child.current_snapshot.files }, as: :json
    assert_response :ok
  end

end
