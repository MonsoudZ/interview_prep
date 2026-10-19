require "test_helper"

class PracticeReviewTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
    load Rails.root.join("db/seeds.rb")
    register("practice@example.test")
  end

  def body = response.parsed_body

  def register(email)
    post "/api/register", params: { name: "Engineer", email: email, password: "practice-password-123" }, as: :json
    assert_response :ok
  end

  def create_interview(track = "ruby", mode = "guided")
    post "/api/sessions", params: { exercise_id: ExerciseVersion.find_by!(track: track).id, mode: mode }, as: :json
    assert_response :created
    body
  end

  def submit_session(record)
    post "/api/sessions/#{record['id']}/start", as: :json
    assert_response :ok
    post "/api/sessions/#{record['id']}/submit", params: { expected_revision: record["revision"] }, as: :json
    assert_response :ok
  end

  def review_entry(rating = "needs_development")
    { "correctness" => { "rating" => rating, "notes" => "The submitted body is still a placeholder.",
      "evidence" => { "path" => "solution.rb", "start_line" => 1, "end_line" => 3 } } }
  end

  def save_review(record, entries: review_entry, version: nil, reflection: "Practice the invariant before coding.")
    put "/api/sessions/#{record['id']}/review", params: { expected_version: version, entries: entries, reflection: reflection }, as: :json
  end

  test "all tracks have progressive support without leaking unrevealed hints" do
    %w[rails ruby system_design].each do |track|
      record = create_interview(track)
      get "/api/sessions/#{record['id']}/practice"
      assert_response :ok
      assert_equal [], body["hints"]
      assert_equal 3, body["total_hints"]
      assert body["can_reveal"]
      3.times do |position|
        post "/api/sessions/#{record['id']}/hint", params: { expected_position: position }, as: :json
        assert_response :ok
        assert_equal position + 1, body["hints"].length
        assert body["hints"].last["body"].present?
      end
      refute body["can_reveal"]
      post "/api/sessions/#{record['id']}/hint", params: { expected_position: 3 }, as: :json
      assert_response :conflict
    end
  end

  test "hint retries cannot accidentally consume an additional level and survive reload" do
    record = create_interview
    2.times { post "/api/sessions/#{record['id']}/hint", params: { expected_position: 0 }, as: :json }
    assert_response :conflict
    get "/api/sessions/#{record['id']}/practice"
    assert_equal 1, body["hints"].length
    assert body["hints"].first["revealed_at"]
    assert_equal 1, InterviewSession.find(record["id"]).hint_reveals.count
  end

  test "assessment and submitted sessions cannot reveal hints including after deadline" do
    record = create_interview("system_design", "assessment")
    post "/api/sessions/#{record['id']}/hint", params: { expected_position: 0 }, as: :json
    assert_response :conflict
    get "/api/sessions/#{record['id']}/practice"
    assert_empty body["hints"]
    refute body["can_reveal"]
    guided = create_interview
    submit_session(guided)
    post "/api/sessions/#{guided['id']}/hint", params: { expected_position: 0 }, as: :json
    assert_response :conflict
  end

  test "reviews require a submission and show rubric for all tracks without fabricated verdicts" do
    %w[rails ruby system_design].each do |track|
      record = create_interview(track)
      get "/api/sessions/#{record['id']}/review"
      assert_response :conflict
      submit_session(record)
      get "/api/sessions/#{record['id']}/review"
      assert_response :ok
      assert_equal "self_assessment", body["kind"]
      assert_equal record["revision"], body["revision"]
      assert body["criteria"].length >= 5
      assert_empty body["executions"]
      assert_empty body["entries"]
      refute body.key?("verdict")
    end
  end

  test "review persists source-bound evidence assistance and transparent next steps" do
    record = create_interview
    post "/api/sessions/#{record['id']}/hint", params: { expected_position: 0 }, as: :json
    submit_session(record)
    save_review(record)
    assert_response :ok
    assert_equal 0, body["version"]
    assert_equal record["revision"], body["revision"]
    assert_equal "solution.rb", body.dig("entries", "correctness", "evidence", "path")
    assert_equal record["files"]["solution.rb"], body.dig("entries", "correctness", "evidence", "excerpt")
    assert_equal ["correctness"], body["next_steps"].map { |step| step["id"] }
    assert_equal 1, body["assistance"].length
    get "/api/sessions/#{record['id']}/review"
    assert_equal "Practice the invariant before coding.", body["reflection"]
    assert_equal record["revision"], SessionReview.first.source_snapshot.revision
    assert_equal record["files"]["solution.rb"], InterviewSession.find(record["id"]).current_snapshot.files["solution.rb"]
  end

  test "stale review cannot overwrite a saved reflection" do
    record = create_interview
    submit_session(record)
    save_review(record)
    assert_response :ok
    save_review(record, version: nil, reflection: "stale tab")
    assert_response :conflict
    save_review(record, version: 0, reflection: "Second reflection")
    assert_response :ok
    assert_equal 1, body["version"]
    save_review(record, version: 0, reflection: "stale update")
    assert_response :conflict
    assert_equal "Second reflection", SessionReview.first.reflection
  end

  test "observed ratings require actual source lines and explanation" do
    record = create_interview
    submit_session(record)
    invalid = [
      { "invented" => review_entry.fetch("correctness") },
      review_entry("pass"),
      { "correctness" => { "rating" => "meets_target", "notes" => "", "evidence" => nil } },
      { "correctness" => review_entry.fetch("correctness").merge("evidence" => { "path" => "../secret", "start_line" => 1, "end_line" => 1 }) },
      { "correctness" => review_entry.fetch("correctness").merge("evidence" => { "path" => "solution.rb", "start_line" => 0, "end_line" => 1 }) },
      { "correctness" => review_entry.fetch("correctness").merge("evidence" => { "path" => "solution.rb", "start_line" => 1, "end_line" => 500 }) },
      { "correctness" => review_entry.fetch("correctness").merge("notes" => "x" * 2001) }
    ]
    invalid.each do |entries|
      save_review(record, entries: entries)
      assert_response :unprocessable_content
    end
    assert_equal 0, SessionReview.count
    save_review(record, entries: { "correctness" => { "rating" => "not_observed", "notes" => "No correctness evidence yet.", "evidence" => nil } })
    assert_response :ok
    assert_empty body["next_steps"]
  end

  test "reflection alone is saveable without inventing observed ratings" do
    record = create_interview
    submit_session(record)
    save_review(record, entries: {})
    assert_response :ok
    assert_empty body["entries"]
  end

  test "review execution evidence excludes preparation and other source revisions" do
    record = create_interview("rails")
    model = InterviewSession.find(record["id"])
    original = model.current_snapshot
    put "/api/sessions/#{record['id']}/snapshot", params: { expected_revision: record["revision"], files: { "app/controllers/events_controller.rb" => "# New submitted revision\n" } }, as: :json
    assert_response :ok
    record = body
    current = model.reload.current_snapshot
    [[original, "tests"], [current, "prepare"], [current, "tests"]].each do |snapshot, purpose|
      model.execution_requests.create!(source_snapshot: snapshot, purpose: purpose, client_request_id: SecureRandom.uuid)
    end
    expected = model.execution_requests.find_by!(source_snapshot: current, purpose: "tests")
    submit_session(record)
    get "/api/sessions/#{record['id']}/review"
    assert_response :ok
    assert_equal [expected.id], body["executions"].map { |execution| execution["id"] }
    assert_nil body["executions"].first["result"]
  end

  test "expired assessments open review on the preserved submission" do
    record = create_interview("system_design", "assessment")
    post "/api/sessions/#{record['id']}/start", as: :json
    assert_response :ok
    model = InterviewSession.find(record["id"])
    model.update!(deadline_at: 1.second.ago)
    get "/api/sessions/#{record['id']}/review"
    assert_response :ok
    assert_equal "submitted", model.reload.status
    assert_equal record["revision"], body["revision"]
    assert_empty body["assistance"]
  end

  test "support and review endpoints enforce account ownership" do
    record = create_interview
    submit_session(record)
    delete "/api/logout", as: :json
    register("another@example.test")
    get "/api/sessions/#{record['id']}/practice"
    assert_response :not_found
    post "/api/sessions/#{record['id']}/hint", params: { expected_position: 0 }, as: :json
    assert_response :not_found
    get "/api/sessions/#{record['id']}/review"
    assert_response :not_found
    save_review(record)
    assert_response :not_found
  end
end
