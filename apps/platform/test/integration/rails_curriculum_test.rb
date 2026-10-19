require "test_helper"

class RailsCurriculumTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
    load Rails.root.join("db/seeds.rb")
    post "/api/register", params: { name: "Curriculum", email: "curriculum@example.test", password: "testing-password-123" }, as: :json
    assert_response :ok
    @old_bridge, @old_signing = ENV.values_at("INTERVIEW_WORKER_BRIDGE_KEY", "INTERVIEW_WORKER_SIGNING_KEY")
    ENV["INTERVIEW_WORKER_BRIDGE_KEY"] = "b" * 40
    ENV["INTERVIEW_WORKER_SIGNING_KEY"] = "s" * 40
  end
  teardown do
    ENV["INTERVIEW_WORKER_BRIDGE_KEY"], ENV["INTERVIEW_WORKER_SIGNING_KEY"] = @old_bridge, @old_signing
  end
  def worker(path, body)
    post "/internal/workers/#{path}", params: body, as: :json, headers: { "Authorization" => "Bearer #{ENV.fetch('INTERVIEW_WORKER_BRIDGE_KEY')}" }
    assert_response :ok
    response.parsed_body
  end
  test "published scenarios expose full repositories hints and submission reviews without leaking references" do
    get "/api/exercises"
    catalog = response.parsed_body.fetch("exercises")
    assert_equal 8, catalog.count { |e| e["track"] == "rails" }
    RailsCurriculum.entries.each do |entry|
      exercise = ExerciseVersion.find_by!(slug: entry.fetch("slug"), version: 1)
      public_entry = catalog.find { |e| e["id"] == exercise.id }
      assert public_entry["executable"]
      assert_equal entry.fetch("skills"), public_entry["skills"]
      assert_equal entry.fetch("test_count"), exercise.starter_files.fetch("test/integration/events_test.rb").scan(/^  test /).length
      assert_equal entry.fetch("test_count"), ExecutionEvidence.expected_tests(exercise)
      assert exercise.starter_files.keys.none? { |path| path.include?("reference") || path.include?("review.json") }
      post "/api/sessions", params: { exercise_id: exercise.id, mode: "guided" }, as: :json
      assert_response :created
      session = response.parsed_body
      assert_includes session.fetch("editable_paths"), "db/schema.rb"
      assert_equal exercise.starter_files.fetch("test/integration/events_test.rb"), session.fetch("files").fetch("test/integration/events_test.rb")
      get "/api/sessions/#{session['id']}/review"; assert_response :conflict
      get "/api/sessions/#{session['id']}/reference"; assert_response :conflict
      post "/api/sessions/#{session['id']}/hint", params: { expected_position: 0 }, as: :json
      assert_response :ok
      assert_equal 1, response.parsed_body.fetch("hints").length
      assert_equal 3, response.parsed_body.fetch("total_hints")
      post "/api/sessions/#{session['id']}/start", as: :json
      assert_response :ok
      post "/api/sessions/#{session['id']}/submit", params: { expected_revision: session.fetch("revision") }, as: :json
      assert_response :ok
      get "/api/sessions/#{session['id']}/review"; assert_response :ok
      review = response.parsed_body
      assert_equal 4, review.fetch("criteria").length
      assert_equal 1, review.fetch("assistance").length
      assert_equal "self_assessment", review.fetch("kind")
      assert review.fetch("reference_available")
      get "/api/sessions/#{session['id']}/reference"; assert_response :ok
      assert response.parsed_body.fetch("files").keys.any? { |path| path.start_with?("app/") }
      assert review.fetch("criteria").all? { |c| c.values_at("target", "probe", "practice").all?(&:present?) }
    end
  end
  test "a legacy worker cannot lease another scenario preparation and capable workers receive exact dispatch" do
    exercise = ExerciseVersion.find_by!(slug: "tenant-projects", version: 1)
    post "/api/sessions", params: { exercise_id: exercise.id, mode: "assessment" }, as: :json
    session = response.parsed_body
    post "/api/sessions/#{session['id']}/prepare", params: { client_request_id: SecureRandom.uuid }, as: :json
    assert_response :accepted
    id = SecureRandom.uuid
    worker("heartbeat", { worker_id: id, capabilities: %w[rails.events.v1 rails.events.prepare.v1] })
    assert_nil worker("lease", { worker_id: id })["job"]
    worker("heartbeat", { worker_id: id, capabilities: ["rails.tenant-projects.v1", "rails.tenant-projects.prepare.v1"] })
    job = worker("lease", { worker_id: id }).fetch("job").fetch("payload")
    assert_equal "rails.tenant-projects.prepare.v1", job.fetch("exercise")
    assert_equal session.fetch("revision"), job.fetch("source_revision")
    assert_equal session.fetch("id"), job.fetch("session_id")
  end
  test "reseeding does not modify published versions or existing snapshots" do
    originals = ExerciseVersion.where(track: "rails").map { |e| [e.id, e.attributes] }.to_h
    load Rails.root.join("db/seeds.rb")
    assert_equal originals, ExerciseVersion.where(track: "rails").map { |e| [e.id, e.attributes] }.to_h
  end
end
