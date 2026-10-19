require "test_helper"

class ReworksTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
    load Rails.root.join("db/seeds.rb")
    post "/api/register", params: { name: "Rework fixture", email: "rework@example.test", password: "rework-password-123" }, as: :json
    assert_response :ok
    @account = Account.find_by!(email: "rework@example.test")
  end
  def body = response.parsed_body
  def source(track = "ruby", version = 2)
    exercise = ExerciseVersion.find_by!(track: track, version: version)
    record = @account.interview_sessions.create!(exercise_version: exercise, mode: "guided")
    Workspace.save!(record, exercise.starter_files.select { |path, _| Workspace.editable?(path, exercise) })
    record.update!(status: "submitted", submitted_revision: record.current_revision, submitted_at: 2.hours.ago)
    record
  end
  def rework(record, **overrides)
    post "/api/sessions/#{record.id}/rework", params: { client_request_id: SecureRandom.uuid, expected_revision: record.submitted_revision,
      mode: "guided", goal: "Synthetic rework fixture: improve the boundary handling." }.merge(overrides), as: :json
  end
  def review(record, rating)
    content = PracticeContent.for(record.exercise_version)
    id = content.fetch("criteria").first.fetch("id")
    value = record.session_review || record.build_session_review(source_snapshot: record.current_snapshot, content_version: content.fetch("version"))
    value.update!(entries: { id => { "rating" => rating, "notes" => "Synthetic fixture, not the user's performance.",
      "evidence" => { "path" => record.current_snapshot.files.keys.first, "start_line" => 1, "end_line" => 1 } } }, reflection: "Fixture reflection")
    record.reload
  end
  def submit(record)
    post "/api/sessions/#{record.id}/start", as: :json
    assert_response :ok
    post "/api/sessions/#{record.id}/submit", params: { expected_revision: record.reload.current_revision }, as: :json
    assert_response :ok
    record.reload
  end

  test "reworks copy the frozen source and exact exercise version across all tracks" do
    [ ["rails", 1], ["ruby", 2], ["system_design", 2] ].each do |track, version|
      original = source(track, version)
      files = original.current_snapshot.files.deep_dup
      rework(original)
      assert_response :created
      child = InterviewSession.find(body.fetch("id"))
      assert_equal original.id, body.fetch("revision_of_id")
      assert_equal original.exercise_version_id, child.exercise_version_id
      assert_equal files, child.current_snapshot.files
      assert_equal "draft", child.status
      assert_nil child.started_at
      assert_nil child.deadline_at
      assert_empty child.execution_requests
      assert_empty child.hint_reveals
      assert_nil child.session_review
      assert_nil child.practice_focus
      refute_equal original.current_snapshot.id, child.current_snapshot.id
      assert_equal files, original.reload.current_snapshot.files
    end
  end

  test "request retries and another tab resume the same rework including after it is submitted" do
    original = source
    request_id = SecureRandom.uuid
    rework(original, client_request_id: request_id)
    assert_response :created
    id = body.fetch("id")
    rework(original, client_request_id: request_id)
    assert_response :ok
    assert_equal id, body.fetch("id")
    assert body["rework_reused"]
    rework(original, mode: "assessment")
    assert_response :ok
    assert_equal id, body.fetch("id")
    assert_equal "guided", body["mode"]
    submit(InterviewSession.find(id))
    rework(original, client_request_id: request_id)
    assert_response :ok
    assert_equal id, body.fetch("id")
    rework(original)
    assert_response :created
    refute_equal id, body.fetch("id")
  end

  test "source review and execution context are captured without inheriting results as new evidence" do
    original = source
    review(original, "needs_development")
    original.hint_reveals.create!(position: 0, content_version: PracticeContent.for(original.exercise_version).fetch("version"))
    run = original.execution_requests.create!(source_snapshot: original.current_snapshot, purpose: "tests", client_request_id: SecureRandom.uuid,
      status: "execution_completed", result: { "output" => "12 runs, 30 assertions, 1 failures, 0 errors, 0 skips" })
    rework(original)
    assert_response :created
    child = InterviewSession.find(body.fetch("id"))
    assert_equal "needs_development", body.dig("revision_context", "self_review", "entries", "correctness", "rating")
    assert_equal run.id, body.dig("revision_context", "reported_execution", "id")
    assert_equal 1, body.dig("revision_context", "prior_hints_revealed")
    review(original, "meets_target")
    get "/api/sessions/#{child.id}"
    assert_equal "needs_development", body.dig("revision_context", "self_review", "entries", "correctness", "rating")
    assert_empty body["executions"]
    get "/api/sessions/#{child.id}/practice"
    assert_empty body["hints"]
    packet = ReviewPacket.build(original)
    assert_nil packet["rework"]
  end

  test "comparison uses saved source distinguishes added and removed files and preserves original" do
    original = source("rails", 1)
    files = original.current_snapshot.files.deep_dup
    rework(original)
    child = InterviewSession.find(body.fetch("id"))
    get "/api/sessions/#{child.id}/rework_comparison"
    assert_response :ok
    assert_empty body["changes"]
    edited = files.except("app/models/application_record.rb").merge("app/models/fix.rb" => "# synthetic added file\n",
      "app/controllers/events_controller.rb" => "# synthetic modified controller\n")
    put "/api/sessions/#{child.id}/snapshot", params: { expected_revision: child.current_revision, files: edited }, as: :json
    assert_response :ok
    get "/api/sessions/#{child.id}/rework_comparison"
    assert_response :ok
    assert_equal %w[added modified removed], body["changes"].map { |item| item["kind"] }.sort
    assert_equal original.submitted_revision, body["source_revision"]
    assert_equal child.reload.current_revision, body["revision"]
    refute body["submitted"]
    assert_equal files, original.reload.current_snapshot.files
    put "/api/sessions/#{original.id}/snapshot", params: { expected_revision: original.current_revision, files: edited }, as: :json
    assert_response :conflict
    assert_equal files, original.reload.current_snapshot.files
  end

  test "submitted rework has its own review and cannot resolve the starter-attempt gap" do
    original = source
    review(original, "needs_development")
    rework(original)
    child = InterviewSession.find(body.fetch("id"))
    submit(child)
    review(child, "meets_target")
    get "/api/sessions/#{child.id}/rework_comparison"
    assert_response :ok
    assert body["review_comparable"]
    assert_equal "needs_development", body["criteria"].first["before"]
    assert_equal "meets_target", body["criteria"].first["after"]
    get "/api/progress"
    assert_response :ok
    assert_equal 2, body.dig("summary", "submitted")
    assert_equal 1, body["plan"].first["observation_count"]
    assert_equal original.id, body["plan"].first.dig("latest", "session_id")
    assert_nil body["plan"].first["next_session_id"]
    assert_equal original.id, body["recent_attempts"].first["revision_of_id"]
    packet = ReviewPacket.build(child)
    assert packet.dig("rework", "prior_work_available")
    assert_equal original.submitted_revision, packet.dig("rework", "source_revision")
  end

  test "design comparisons preserve the complete diagram and all note sections" do
    original = source("system_design", 2)
    rework(original)
    child = InterviewSession.find(body.fetch("id"))
    edited = child.current_snapshot.files.merge("reliability.md" => "# Synthetic rework fixture\nAcknowledge only after a durable write.\n")
    put "/api/sessions/#{child.id}/snapshot", params: { expected_revision: child.current_revision, files: edited }, as: :json
    assert_response :ok
    get "/api/sessions/#{child.id}/rework_comparison"
    assert_response :ok
    assert_equal ["reliability.md"], body["changes"].map { |item| item["path"] }
    assert body["before_design"].is_a?(Hash)
    assert_equal body["before_design"], body["after_design"]
    assert_equal 6, body["unchanged_files"]
  end

  test "timed rework has an independent timer and enforces the existing preparation requirement" do
    original = source
    rework(original, mode: "assessment")
    assert_response :created
    child = InterviewSession.find(body.fetch("id"))
    assert_nil child.deadline_at
    post "/api/sessions/#{child.id}/start", as: :json
    assert_response :conflict
    design = source("system_design", 2)
    rework(design, mode: "assessment")
    child = InterviewSession.find(body.fetch("id"))
    post "/api/sessions/#{child.id}/start", as: :json
    assert_response :ok
    assert child.reload.deadline_at > Time.current
    assert_equal "submitted", design.reload.status
    assert_nil design.deadline_at
  end

  test "quota applies to new reworks but does not prevent resuming an existing one" do
    original = source
    rework(original)
    id = body.fetch("id")
    9.times { @account.interview_sessions.create!(exercise_version: original.exercise_version, mode: "guided") }
    rework(original)
    assert_response :ok
    assert_equal id, body.fetch("id")
    another = source
    rework(another)
    assert_response :too_many_requests
    assert_equal 1, InterviewSession.where(revision_of_id: original.id).count
  end

  test "identity validation submission guards account ownership and comparison authorization" do
    original = source
    rework(original, goal: " ")
    assert_response :unprocessable_content
    rework(original, goal: "x" * 1501)
    assert_response :unprocessable_content
    rework(original, client_request_id: "bad")
    assert_response :unprocessable_content
    rework(original, mode: "unknown")
    assert_response :unprocessable_content
    rework(original, expected_revision: "stale")
    assert_response :conflict
    get "/api/sessions/#{original.id}/rework_comparison"
    assert_response :conflict
    rework(original)
    child_id = body.fetch("id")
    rework(InterviewSession.find(child_id), expected_revision: body.fetch("revision"))
    assert_response :conflict
    delete "/api/logout", as: :json
    get "/api/sessions/#{original.id}/rework"
    assert_response :unauthorized
    post "/api/register", params: { name: "Other", email: "other-rework@example.test", password: "other-rework-password-123" }, as: :json
    ["/api/sessions/#{original.id}/rework", "/api/sessions/#{child_id}/rework_comparison"].each do |path|
      get path
      assert_response :not_found
    end
    rework(original)
    assert_response :not_found
  end
end
