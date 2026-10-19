require "test_helper"

class SessionTimelineTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
    load Rails.root.join("db/seeds.rb")
    post "/api/register", params: { name: "Replay fixture", email: "replay@example.test", password: "replay-password-123" }, as: :json
    assert_response :ok
  end
  def body = response.parsed_body
  def save(id, revision, files)
    put "/api/sessions/#{id}/snapshot", params: { expected_revision: revision, files: files }, as: :json
    assert_response :ok
    body.fetch("revision")
  end

  test "timeline replays saved revisions with changed paths, hints, runs and the diff for one step" do
    exercise = ExerciseVersion.find_by!(slug: "repository-events", version: 1)
    post "/api/sessions", params: { exercise_id: exercise.id, mode: "guided" }, as: :json
    assert_response :created
    id, revision = body.fetch("id"), body.fetch("revision")
    files = InterviewSession.find(id).current_snapshot.files
    travel 2.minutes
    second = save(id, revision, files.merge("app/controllers/events_controller.rb" => "# first attempt\n"))
    travel 30.seconds
    post "/api/sessions/#{id}/hint", params: { expected_position: 0 }, as: :json
    assert_response :ok
    record = InterviewSession.find(id)
    record.execution_requests.create!(source_snapshot: record.current_snapshot, purpose: "tests", client_request_id: SecureRandom.uuid,
      status: "execution_completed", result: { "output" => "12 runs, 30 assertions, 1 failures, 0 errors, 0 skips\n" })
    travel 1.minute
    third = save(id, second, files.merge("app/controllers/events_controller.rb" => "# second attempt\n", "app/models/extra.rb" => "# added\n"))
    post "/api/sessions/#{id}/start", as: :json
    assert_response :ok
    post "/api/sessions/#{id}/submit", params: { expected_revision: third }, as: :json
    assert_response :ok

    get "/api/sessions/#{id}/timeline"
    assert_response :ok
    steps = body.fetch("steps")
    assert_equal [revision, second, third], steps.map { |step| step["revision"] }
    assert_equal [0, 120, 210], steps.map { |step| step["offset_seconds"] }
    assert_equal [], steps[0]["changed_paths"], "the opening revision equals the editable starter"
    assert_equal ["app/controllers/events_controller.rb"], steps[1]["changed_paths"]
    assert_equal ["app/controllers/events_controller.rb", "app/models/extra.rb"], steps[2]["changed_paths"]
    assert_equal [0], steps[1]["hints"]
    assert_equal 11, steps[1]["executions"].first.dig("summary", "passed")
    assert_equal [], steps[2]["executions"]
    assert_equal [false, false, true], steps.map { |step| step["submitted"] }
    assert_nil body["changes"]

    get "/api/sessions/#{id}/timeline", params: { revision: third }
    assert_response :ok
    changes = body.fetch("changes")
    assert_equal %w[app/controllers/events_controller.rb app/models/extra.rb], changes.map { |item| item["path"] }
    assert_equal %w[modified added], changes.map { |item| item["kind"] }
    assert_equal "# first attempt\n", changes.first["before"]
    assert_equal "# second attempt\n", changes.first["after"]

    get "/api/sessions/#{id}/timeline", params: { revision: "0" * 64 }
    assert_response :not_found
  end

  test "another account cannot replay a private session" do
    exercise = ExerciseVersion.find_by!(track: "ruby")
    post "/api/sessions", params: { exercise_id: exercise.id, mode: "guided" }, as: :json
    id = body.fetch("id")
    delete "/api/logout", as: :json
    post "/api/register", params: { name: "Other", email: "other@example.test", password: "other-password-123" }, as: :json
    get "/api/sessions/#{id}/timeline"
    assert_response :not_found
  end
end
