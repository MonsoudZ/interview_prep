require "test_helper"
require "open3"
require "tmpdir"

# Opt-in integration. When enabled, missing Linux/Docker/runsc is a failure, never a pass.
class LiveWorkerTest < ActionDispatch::IntegrationTest
  setup do
    @old_bridge = ENV["INTERVIEW_WORKER_BRIDGE_KEY"]
    @old_signing = ENV["INTERVIEW_WORKER_SIGNING_KEY"]
    skip "Set RUN_LINUX_WORKER_INTEGRATION=1 on the Linux validation host" unless ENV["RUN_LINUX_WORKER_INTEGRATION"] == "1"
    assert_match(/\Asha256:[0-9a-f]{64}\z/, ENV.fetch("INTERVIEW_WORKER_IMAGE"), "Set the real immutable image ID")
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

  def data
    response.parsed_body
  end

  def worker_post(path, params)
    post path, params: params, as: :json,
      headers: { "Authorization" => "Bearer #{ENV.fetch('INTERVIEW_WORKER_BRIDGE_KEY')}" }
    assert_response :ok, "#{path}: #{response.body}"
    data
  end

  def execute_queued
    worker_post("/internal/workers/heartbeat", { worker_id: @worker_id, capabilities: WorkerJobs::OPERATIONS })
    leased = worker_post("/internal/workers/lease", { worker_id: @worker_id })
    assert leased["job"], "Expected the test's queued job"
    output = nil
    Dir.mktmpdir("interview-live-receipts") do |directory|
      root = Rails.root.join("../..").expand_path
      command = if ENV["INTERVIEW_COLIMA_PROFILE"].present?
        ["python3", root.join("services/local_vm/execute.py").to_s, "--profile", ENV.fetch("INTERVIEW_COLIMA_PROFILE"), "--image", ENV.fetch("INTERVIEW_WORKER_IMAGE")]
      else
        ["python3", root.join("services/execution_worker/worker.py").to_s, "run", "--image", ENV.fetch("INTERVIEW_WORKER_IMAGE"), "--state", File.join(directory, "receipts.sqlite3")]
      end
      stdout, stderr, status = Open3.capture3({ "INTERVIEW_WORKER_SIGNING_KEY" => ENV.fetch("INTERVIEW_WORKER_SIGNING_KEY") },
        *command,
        stdin_data: JSON.generate(leased.fetch("job")))
      assert status.success?, "Real worker rejected execution: #{stderr}"
      output = JSON.parse(stdout)
    end
    assert_equal leased.fetch("job").fetch("payload").fetch("job_id"), output.fetch("job_id")
    assert ExecutionRequest.exists?(output.fetch("job_id")), "Leased execution disappeared during VM work: #{leased.fetch('job').fetch('payload').fetch('exercise')}"
    worker_post("/internal/executions/#{output.fetch('job_id')}/result", { lease_token: leased.fetch("lease_token"), result: output })
    output
  end

  test "real queued Rails preparation failure success and immutable submission" do
    post "/api/register", params: { name: "Linux validation", email: "live-#{SecureRandom.hex(6)}@example.test", password: SecureRandom.hex(20) }, as: :json
    assert_response :ok
    exercise = ExerciseVersion.find_by!(slug: "repository-events", version: 1)
    post "/api/sessions", params: { exercise_id: exercise.id, mode: "assessment" }, as: :json
    assert_response :created
    session_id = data.fetch("id")
    revision = data.fetch("revision")

    post "/api/sessions/#{session_id}/prepare", params: { client_request_id: SecureRandom.uuid }, as: :json
    assert_response :accepted
    prepared = execute_queued
    assert_equal "execution_completed", prepared.fetch("status"), prepared["output"]
    post "/api/sessions/#{session_id}/start", as: :json
    assert_response :ok

    post "/api/sessions/#{session_id}/execute", params: { client_request_id: SecureRandom.uuid }, as: :json
    assert_response :accepted
    starter = execute_queued
    assert_equal "execution_failed", starter.fetch("status"), starter["output"]
    assert_match(/12 runs, 12 assertions, 12 failures, 0 errors, 0 skips/, starter.fetch("output"))

    root = Rails.root.join("../..").expand_path
    source = root.join("experiments/rails-runtime/reference")
    files = InterviewSession.find(session_id).current_snapshot.files.merge(
      Dir.glob(source.join("app/**/*.rb")).to_h { |path| [Pathname.new(path).relative_path_from(source).to_s, File.read(path)] })
    # Trusted probe code verifies observable runtime behavior, not isolation against every attack.
    files["app/controllers/application_controller.rb"] = <<~RUBY
      require "json"
      require "socket"
      probe = { uid: Process.uid, docker_socket_present: File.exist?("/var/run/docker.sock") }
      probe[:root_writable] = begin
        File.write("/opt/exercise/unexpected-probe-write", "x"); true
      rescue SystemCallError
        false
      end
      probe[:external_tcp_connected] = begin
        Socket.tcp("1.1.1.1", 443, connect_timeout: 1) { |socket| socket.close }; true
      rescue SystemCallError, IOError
        false
      end
      puts "WORKER_PROBE:" + JSON.generate(probe)
      class ApplicationController < ActionController::API; end
    RUBY
    put "/api/sessions/#{session_id}/snapshot", params: { expected_revision: revision, files: files }, as: :json
    assert_response :ok
    reference_revision = data.fetch("revision")
    post "/api/sessions/#{session_id}/execute", params: { client_request_id: SecureRandom.uuid }, as: :json
    assert_response :accepted
    reference = execute_queued
    assert_equal "execution_completed", reference.fetch("status"), reference["output"]
    assert_match(/12 runs, 158 assertions, 0 failures, 0 errors, 0 skips/, reference.fetch("output"))
    probe_line = reference.fetch("output").lines.find { |line| line.start_with?("WORKER_PROBE:") }
    assert probe_line, "Runtime observations are missing"
    assert_equal({ "uid" => 1000, "docker_socket_present" => false, "root_writable" => false,
                   "external_tcp_connected" => false }, JSON.parse(probe_line.delete_prefix("WORKER_PROBE:")))
    assert_equal reference_revision, reference.fetch("source_revision")

    get "/api/sessions/#{session_id}"
    assert_response :ok
    assert_equal reference_revision, data.fetch("executions").first.fetch("revision")
    post "/api/sessions/#{session_id}/submit", params: { expected_revision: reference_revision }, as: :json
    assert_response :ok
    assert_equal reference_revision, data.fetch("submitted_revision")
    put "/api/sessions/#{session_id}/snapshot", params: { expected_revision: reference_revision, files: files }, as: :json
    assert_response :conflict
  end
  test "every published Rails scenario prepares fails on starter and passes its reference in Linux" do
    post "/api/register", params: { name: "Curriculum VM validation", email: "curriculum-live-#{SecureRandom.hex(6)}@example.test", password: SecureRandom.hex(20) }, as: :json
    assert_response :ok
    RailsCurriculum.entries.each do |entry|
      exercise = ExerciseVersion.find_by!(slug: entry.fetch("slug"), version: 1)
      post "/api/sessions", params: { exercise_id: exercise.id, mode: "guided" }, as: :json
      assert_response :created
      session_id, revision = data.values_at("id", "revision")
      post "/api/sessions/#{session_id}/prepare", params: { client_request_id: SecureRandom.uuid }, as: :json
      assert_response :accepted
      prepared = execute_queued
      assert_equal "execution_completed", prepared.fetch("status"), prepared["output"]
      post "/api/sessions/#{session_id}/execute", params: { client_request_id: SecureRandom.uuid }, as: :json
      assert_response :accepted
      starter = execute_queued
      assert_equal "execution_failed", starter.fetch("status"), starter["output"]
      assert_match(/12 runs,/, starter.fetch("output"))
      root = Rails.root.join("../../curriculum/rails", entry.fetch("slug"), "reference")
      files = InterviewSession.find(session_id).current_snapshot.files.merge(
        Dir.glob(root.join("**/*.rb")).to_h { |path| [Pathname.new(path).relative_path_from(root).to_s, File.read(path)] })
      put "/api/sessions/#{session_id}/snapshot", params: { expected_revision: revision, files: files }, as: :json
      assert_response :ok
      reference_revision = data.fetch("revision")
      post "/api/sessions/#{session_id}/execute", params: { client_request_id: SecureRandom.uuid }, as: :json
      assert_response :accepted
      reference = execute_queued
      assert_equal "execution_completed", reference.fetch("status"), "#{entry.fetch('slug')}: #{reference['output']}"
      assert_match(/12 runs, \d+ assertions, 0 failures, 0 errors, 0 skips/, reference.fetch("output"))
      assert_equal reference_revision, reference.fetch("source_revision")
    end
  end

  test "Ruby code runs visible supplemental and scale checks in Linux with revision binding" do
    post "/api/register", params: { name: "Ruby VM validation", email: "ruby-live-#{SecureRandom.hex(6)}@example.test", password: SecureRandom.hex(20) }, as: :json
    assert_response :ok
    exercise = ExerciseVersion.find_by!(slug: "merge-intervals", version: 2)
    post "/api/sessions", params: { exercise_id: exercise.id, mode: "assessment" }, as: :json
    assert_response :created
    session_id, revision = data.values_at("id", "revision")
    post "/api/sessions/#{session_id}/prepare", params: { client_request_id: SecureRandom.uuid }, as: :json
    assert_response :accepted
    prepared = execute_queued
    assert_equal "execution_completed", prepared.fetch("status"), prepared["output"]
    assert_includes prepared.fetch("output"), "implementation has not been executed"
    post "/api/sessions/#{session_id}/start", as: :json
    assert_response :ok
    post "/api/sessions/#{session_id}/execute", params: { client_request_id: SecureRandom.uuid }, as: :json
    assert_response :accepted
    starter = execute_queued
    assert_equal "execution_failed", starter.fetch("status"), starter["output"]
    assert_match(/12 runs, \d+ assertions, 12 failures, 0 errors, 0 skips/, starter.fetch("output"))
    reference = File.read(Rails.root.join("../../curriculum/ruby/merge-intervals/reference/solution.rb"))
    put "/api/sessions/#{session_id}/snapshot", params: { expected_revision: revision, files: { "solution.rb" => reference } }, as: :json
    assert_response :ok
    revision = data.fetch("revision")
    post "/api/sessions/#{session_id}/execute", params: { client_request_id: SecureRandom.uuid }, as: :json
    assert_response :accepted
    result = execute_queued
    assert_equal "execution_completed", result.fetch("status"), result["output"]
    assert_match(/12 runs, 112 assertions, 0 failures, 0 errors, 0 skips/, result.fetch("output"))
    assert_equal revision, result.fetch("source_revision")
    post "/api/sessions/#{session_id}/submit", params: { expected_revision: revision }, as: :json
    assert_response :ok
    get "/api/sessions/#{session_id}/reference"
    assert_response :ok
    assert_equal reference, data.fetch("files").fetch("solution.rb")
    put "/api/sessions/#{session_id}/snapshot", params: { expected_revision: revision, files: { "solution.rb" => "# cannot overwrite" } }, as: :json
    assert_response :conflict
  end

end
