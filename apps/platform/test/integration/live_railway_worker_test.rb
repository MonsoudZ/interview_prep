require "test_helper"
require "open3"

# Billable opt-in: three real Railway sandbox runs against an already built
# checkpoint. Missing configuration is a failure when explicitly enabled.
class LiveRailwayWorkerTest < ActionDispatch::IntegrationTest
  setup do
    @old_bridge = ENV["INTERVIEW_WORKER_BRIDGE_KEY"]
    @old_signing = ENV["INTERVIEW_WORKER_SIGNING_KEY"]
    skip "Set RUN_RAILWAY_WORKER_INTEGRATION=1 after configuring the Railway runtime and budget" unless ENV["RUN_RAILWAY_WORKER_INTEGRATION"] == "1"
    assert_equal "1", ENV["INTERVIEW_RAILWAY_EXECUTION_ENABLED"]
    assert ENV["RAILWAY_API_TOKEN"].present?, "Configure the Railway API token securely"
    assert ENV["RAILWAY_ENVIRONMENT_ID"].present?, "Choose the interview project's environment"
    Rails.cache.clear
    load Rails.root.join("db/seeds.rb")
    ENV["INTERVIEW_WORKER_BRIDGE_KEY"] = SecureRandom.hex(32)
    ENV["INTERVIEW_WORKER_SIGNING_KEY"] = SecureRandom.hex(32)
    @worker_id = SecureRandom.uuid
  end
  teardown do
    ENV["INTERVIEW_WORKER_BRIDGE_KEY"] = @old_bridge
    ENV["INTERVIEW_WORKER_SIGNING_KEY"] = @old_signing
  end

  def data = response.parsed_body

  def worker_post(path, params)
    post path, params: params, as: :json,
      headers: { "Authorization" => "Bearer #{ENV.fetch('INTERVIEW_WORKER_BRIDGE_KEY')}" }
    assert_response :ok
    data
  end

  def execute_queued
    worker_post("/internal/workers/heartbeat", { worker_id: @worker_id, capabilities: WorkerJobs::OPERATIONS })
    leased = worker_post("/internal/workers/lease", { worker_id: @worker_id })
    assert leased["job"], "Expected queued work"
    script = Rails.root.join("../../services/railway_worker/cli.mjs").expand_path.to_s
    stdout, stderr, status = Open3.capture3({ "INTERVIEW_WORKER_ID" => @worker_id,
      "INTERVIEW_CONTROL_PLANE_URL" => "http://127.0.0.1:3100" }, "node", script, "run", stdin_data: JSON.generate(leased.fetch("job")))
    assert status.success?, "Railway worker could not execute: #{stderr}"
    result = JSON.parse(stdout)
    worker_post("/internal/executions/#{result.fetch('job_id')}/result", { lease_token: leased.fetch("lease_token"), result: result })
    result
  end

  test "Railway sandbox preparation starter reference and submitted revision end to end" do
    post "/api/register", params: { name: "Railway validation", email: "railway-#{SecureRandom.hex(6)}@example.test", password: SecureRandom.hex(20) }, as: :json
    assert_response :ok
    exercise = ExerciseVersion.find_by!(slug: "repository-events", version: 1)
    post "/api/sessions", params: { exercise_id: exercise.id, mode: "assessment" }, as: :json
    assert_response :created
    session_id = data.fetch("id")
    revision = data.fetch("revision")
    post "/api/sessions/#{session_id}/prepare", params: { client_request_id: SecureRandom.uuid }, as: :json
    assert_response :accepted
    prepared = execute_queued
    assert_equal "execution_completed", prepared["status"], prepared["output"]
    assert_match(/uid=20000; network=none; privileges=dropped/, prepared["output"])
    post "/api/sessions/#{session_id}/start", as: :json
    assert_response :ok
    post "/api/sessions/#{session_id}/execute", params: { client_request_id: SecureRandom.uuid }, as: :json
    assert_response :accepted
    starter = execute_queued
    assert_equal "execution_failed", starter["status"], starter["output"]
    assert_match(/12 runs, 12 assertions, 12 failures, 0 errors, 0 skips/, starter["output"])

    source = Rails.root.join("../../experiments/rails-runtime/reference").expand_path
    files = InterviewSession.find(session_id).current_snapshot.files.merge(
      Dir.glob(source.join("app/**/*.rb")).to_h { |path| [Pathname.new(path).relative_path_from(source).to_s, File.read(path)] })
    put "/api/sessions/#{session_id}/snapshot", params: { expected_revision: revision, files: files }, as: :json
    assert_response :ok
    reference_revision = data.fetch("revision")
    post "/api/sessions/#{session_id}/execute", params: { client_request_id: SecureRandom.uuid }, as: :json
    assert_response :accepted
    reference = execute_queued
    assert_equal "execution_completed", reference["status"], reference["output"]
    assert_equal "railway_sandbox", reference["runtime_provider"]
    assert_match(/12 runs, 158 assertions, 0 failures, 0 errors, 0 skips/, reference["output"])
    assert_equal reference_revision, reference["source_revision"]
    get "/api/sessions/#{session_id}"
    assert_equal 12, data.fetch("executions").first.fetch("reported_test_summary").fetch("passed")
    post "/api/sessions/#{session_id}/submit", params: { expected_revision: reference_revision }, as: :json
    assert_response :ok
    assert_equal reference_revision, data.fetch("submitted_revision")
    put "/api/sessions/#{session_id}/snapshot", params: { expected_revision: reference_revision, files: files }, as: :json
    assert_response :conflict
  end
end
