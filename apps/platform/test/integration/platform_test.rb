require "test_helper"
require "open3"

class PlatformTest < ActionDispatch::IntegrationTest
  PASSWORD = "testing-password-123"
  setup do
    Rails.cache.clear
    load Rails.root.join("db/seeds.rb")
    @old_bridge = ENV["INTERVIEW_WORKER_BRIDGE_KEY"]
    @old_signing = ENV["INTERVIEW_WORKER_SIGNING_KEY"]
    ENV["INTERVIEW_WORKER_BRIDGE_KEY"] = "b" * 40
    ENV["INTERVIEW_WORKER_SIGNING_KEY"] = "s" * 40
    @worker = SecureRandom.uuid
  end
  teardown do
    ENV["INTERVIEW_WORKER_BRIDGE_KEY"] = @old_bridge
    ENV["INTERVIEW_WORKER_SIGNING_KEY"] = @old_signing
    ActionController::Base.allow_forgery_protection = false
  end

  def body
    response.parsed_body
  end
  def register(email = "engineer@example.com")
    post "/api/register", params: { name: "Engineer", email: email, password: PASSWORD }, as: :json
    assert_response :ok
    body.fetch("account")
  end
  def create_interview(track = "rails", mode = "guided")
    exercise = ExerciseVersion.find_by!(track: track)
    post "/api/sessions", params: { exercise_id: exercise.id, mode: mode }, as: :json
    assert_response :created
    body
  end
  def operation(id, action, extra = {})
    post "/api/sessions/#{id}/#{action}", params: { client_request_id: SecureRandom.uuid }.merge(extra), as: :json
  end
  def worker_post(path, data)
    post path, params: data, as: :json, headers: { "Authorization" => "Bearer #{ENV.fetch('INTERVIEW_WORKER_BRIDGE_KEY')}" }
  end
  def heartbeat
    worker_post("/internal/workers/heartbeat", { worker_id: @worker, capabilities: WorkerJobs::OPERATIONS })
    assert_response :ok
  end
  def lease
    heartbeat
    worker_post("/internal/workers/lease", { worker_id: @worker })
    assert_response :ok
    body
  end
  def deliver(leased, changes = {})
    payload = leased.fetch("job").fetch("payload")
    result = payload.slice("job_id", "tenant_id", "session_id", "source_revision").merge(
      "version" => 1, "status" => "execution_completed", "exit_code" => 0,
      "output" => "Synthetic worker transport fixture; not real execution", "duration_seconds" => 0.1).merge(changes)
    worker_post("/internal/executions/#{payload.fetch('job_id')}/result", { lease_token: leased.fetch("lease_token"), result: result })
  end

  test "private resources require authentication" do
    get "/api/exercises"
    assert_response :unauthorized
    get "/api/sessions"
    assert_response :unauthorized
  end

  test "register login logout and normalized account identity" do
    account = register("ENGINEER@example.com")
    assert_equal "engineer@example.com", account["email"]
    refute account.key?("password_digest")
    delete "/api/logout", as: :json
    get "/api/sessions"
    assert_response :unauthorized
    post "/api/login", params: { email: "engineer@example.com", password: "wrong" }, as: :json
    assert_response :unauthorized
    post "/api/login", params: { email: "engineer@example.com", password: PASSWORD }, as: :json
    assert_response :ok
  end

  test "rejects weak passwords and duplicate email" do
    post "/api/register", params: { name: "Engineer", email: "a@example.com", password: "short" }, as: :json
    assert_response :unprocessable_content
    register
    post "/api/register", params: { name: "Engineer", email: "engineer@example.com", password: PASSWORD }, as: :json
    assert_response :unprocessable_content
  end

  test "csrf applies to browser mutations" do
    ActionController::Base.allow_forgery_protection = true
    post "/api/register", params: { name: "Engineer", email: "csrf@example.com", password: PASSWORD }, as: :json
    assert_response :unprocessable_content
    get "/api/bootstrap"
    token = body.fetch("csrf_token")
    post "/api/register", params: { name: "Engineer", email: "csrf@example.com", password: PASSWORD }, as: :json, headers: { "X-CSRF-Token" => token }
    assert_response :ok
  end

  test "login is rate limited" do
    11.times { post "/api/login", params: { email: "missing@example.com", password: "wrong" }, as: :json }
    assert_response :too_many_requests
  end

  test "catalog contains three tracks without fake worker availability" do
    register
    get "/api/exercises"
    assert_equal %w[rails ruby system_design], body.fetch("exercises").map { |e| e["track"] }.uniq.sort
    assert body["exercises"].none? { |e| e["worker_available"] }
  end

  test "saved session survives another authenticated browser session" do
    register
    record = create_interview
    edits = InterviewSession.find(record["id"]).current_snapshot.files.merge("app/models/event.rb" => "class Event < ApplicationRecord; end\n")
    put "/api/sessions/#{record['id']}/snapshot", params: { expected_revision: record["revision"], files: edits }, as: :json
    assert_response :ok
    revision = body["revision"]
    delete "/api/logout", as: :json
    post "/api/login", params: { email: "engineer@example.com", password: PASSWORD }, as: :json
    get "/api/sessions/#{record['id']}"
    assert_equal revision, body["revision"]
    assert_equal edits["app/models/event.rb"], body["files"]["app/models/event.rb"]
  end

  test "owner cannot read or mutate another account session" do
    register
    record = create_interview
    delete "/api/logout", as: :json
    register("other@example.com")
    get "/api/sessions/#{record['id']}"
    assert_response :not_found
    operation(record["id"], "start")
    assert_response :not_found
    get "/api/sessions"
    assert_empty body["sessions"]
  end

  test "stale save does not overwrite acknowledged snapshot" do
    register
    record = create_interview
    files = { "app/models/event.rb" => "# first\n" }
    put "/api/sessions/#{record['id']}/snapshot", params: { expected_revision: record["revision"], files: files }, as: :json
    assert_response :ok
    put "/api/sessions/#{record['id']}/snapshot", params: { expected_revision: record["revision"], files: { "app/models/event.rb" => "# stale\n" } }, as: :json
    assert_response :conflict
    assert_equal files, InterviewSession.find(record["id"]).current_snapshot.files
  end

  test "rejects path traversal protected test files and invalid maps" do
    register
    record = create_interview
    [{ "../escape.rb" => "bad" }, { "test/integration/events_test.rb" => "bad" }, ["invalid"]].each do |files|
      put "/api/sessions/#{record['id']}/snapshot", params: { expected_revision: record["revision"], files: files }, as: :json
      assert_response :unprocessable_content
    end
  end

  test "assessment cannot start before preparation" do
    register
    record = create_interview("rails", "assessment")
    operation(record["id"], "start")
    assert_response :conflict
    assert_nil InterviewSession.find(record["id"]).deadline_at
  end

  test "successful prepare lease enables timed start" do
    register
    record = create_interview("rails", "assessment")
    operation(record["id"], "prepare")
    assert_response :accepted
    leased = lease
    assert_equal "rails.events.prepare.v1", leased["job"]["payload"]["exercise"]
    deliver(leased)
    assert_response :ok
    operation(record["id"], "start")
    assert_response :ok
    assert_equal "active", body["status"]
    assert_in_delta 50.minutes, Time.parse(body["deadline_at"]) - Time.current, 2
  end

  test "duplicate preparation requests preserve readiness after completion" do
    register
    record = create_interview("rails", "assessment")
    key = SecureRandom.uuid
    2.times do
      operation(record["id"], "prepare", client_request_id: key)
      assert_response :accepted
    end
    assert_equal 1, InterviewSession.find(record["id"]).execution_requests.count
    deliver(lease)
    operation(record["id"], "prepare", client_request_id: key)
    assert_response :accepted
    assert_equal "ready", body["status"]
    assert_nil body["deadline_at"]
    assert_equal 1, InterviewSession.find(record["id"]).execution_requests.count
  end

  test "source changed during preparation cannot become ready" do
    register
    record = create_interview("rails", "assessment")
    operation(record["id"], "prepare")
    leased = lease
    put "/api/sessions/#{record['id']}/snapshot", params: { expected_revision: record["revision"], files: { "app/models/event.rb" => "# new\n" } }, as: :json
    assert_response :ok
    deliver(leased)
    assert_equal "draft", InterviewSession.find(record["id"]).status
  end

  test "prepared assessment waits when its worker is no longer connected" do
    register
    record = create_interview("rails", "assessment")
    operation(record["id"], "prepare")
    leased = lease
    deliver(leased)
    WorkerNode.find(@worker).update!(last_seen_at: 1.minute.ago)
    operation(record["id"], "start")
    assert_response :conflict
    assert_nil InterviewSession.find(record["id"]).deadline_at
  end

  test "result cannot claim completed with an unsuccessful exit code" do
    register
    record = create_interview
    operation(record["id"], "execute")
    leased = lease
    deliver(leased, "exit_code" => 1)
    assert_response :unprocessable_content
    assert_equal "leased", ExecutionRequest.first.status
  end

  test "Railway result callback validates provider and presents reported counts for its revision" do
    register
    record = create_interview
    operation(record["id"], "execute")
    leased = lease
    deliver(leased, "runtime_provider" => "unknown-provider")
    assert_response :unprocessable_content
    deliver(leased, "runtime_provider" => "railway_sandbox", "output" => "Synthetic transport fixture only\n12 runs, 158 assertions, 0 failures, 0 errors, 0 skips\n")
    assert_response :ok
    get "/api/sessions/#{record['id']}"
    assert_response :ok
    result = body.fetch("executions").first
    assert_equal "railway_sandbox", result.fetch("result").fetch("runtime_provider")
    assert_equal record["revision"], result.fetch("revision")
    assert_equal 12, result.fetch("reported_test_summary").fetch("passed")
    assert result.fetch("reported_test_summary").fetch("reported")
  end

  test "deadline submits last acknowledged revision and rejects late save" do
    register
    record = create_interview("system_design", "assessment")
    operation(record["id"], "start")
    model = InterviewSession.find(record["id"])
    model.update!(deadline_at: 1.second.ago)
    put "/api/sessions/#{record['id']}/snapshot", params: { expected_revision: record["revision"], files: { "notes.md" => "late" } }, as: :json
    assert_response :conflict
    model.reload
    assert_equal "submitted", model.status
    assert_equal record["revision"], model.submitted_revision
    assert_equal model.deadline_at, model.submitted_at
  end

  test "submission is immutable and repeat submit is idempotent" do
    register
    record = create_interview
    operation(record["id"], "start")
    operation(record["id"], "submit", expected_revision: record["revision"])
    assert_response :ok
    submitted = body["submitted_revision"]
    operation(record["id"], "submit", expected_revision: "other")
    assert_response :ok
    assert_equal submitted, body["submitted_revision"]
    put "/api/sessions/#{record['id']}/snapshot", params: { expected_revision: record["revision"], files: { "app/models/event.rb" => "changed" } }, as: :json
    assert_response :conflict
  end

  test "execution requests are idempotent and pending quota applies" do
    register
    record = create_interview
    key = SecureRandom.uuid
    2.times { operation(record["id"], "execute", client_request_id: key); assert_response :accepted }
    assert_equal 1, ExecutionRequest.count
    2.times { operation(record["id"], "execute"); assert_response :accepted }
    operation(record["id"], "execute")
    assert_response :too_many_requests
  end

  test "worker auth and one concurrent lease per worker" do
    register
    record = create_interview
    2.times { operation(record["id"], "execute") }
    post "/internal/workers/lease", params: { worker_id: @worker }, as: :json
    assert_response :unauthorized
    first = lease
    assert first["job"]
    worker_post("/internal/workers/lease", { worker_id: @worker })
    assert_nil body["job"]
    assert_equal 1, ExecutionRequest.where(status: "leased").count
  end

  test "result rejects wrong lease and mismatched revision" do
    register
    record = create_interview
    operation(record["id"], "execute")
    leased = lease
    deliver(leased.merge("lease_token" => "wrong"))
    assert_response :unauthorized
    deliver(leased, "source_revision" => "wrong")
    assert_response :conflict
    deliver(leased)
    assert_response :ok
    deliver(leased, "output" => "must not replace original")
    assert_response :ok
    assert_match "Synthetic worker", ExecutionRequest.first.result["output"]
  end

  test "expired leases become infrastructure failures rather than fabricated test failures" do
    register
    record = create_interview
    operation(record["id"], "execute")
    lease
    ExecutionRequest.first.update!(lease_expires_at: 1.second.ago)
    WorkerJobs.expire_leases!
    assert_equal "infrastructure_error", ExecutionRequest.first.status
  end

  test "workspace polling resolves an expired lease when its worker disappeared" do
    register
    record = create_interview
    operation(record["id"], "execute")
    lease
    ExecutionRequest.first.update!(lease_expires_at: 1.second.ago)
    get "/api/sessions/#{record['id']}"
    assert_response :ok
    execution = body.fetch("executions").first
    assert_equal "infrastructure_error", execution.fetch("status")
    assert_nil execution["reported_test_summary"]
    assert_match "lease expired", execution.fetch("result").fetch("output")
  end

  test "published exercise versions and snapshots cannot be updated" do
    register
    record = create_interview
    assert_raises(ActiveRecord::ReadOnlyRecord) { ExerciseVersion.first.update!(title: "changed") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { InterviewSession.find(record["id"]).current_snapshot.update!(files: {}) }
  end

  test "Ruby issued jobs verify with the Python worker contract" do
    register
    record = create_interview
    operation(record["id"], "execute")
    envelope = WorkerJobs.envelope(ExecutionRequest.first)
    worker_path = Rails.root.join("../../services/execution_worker").expand_path.to_s
    code = "import sys,json,os; sys.path.insert(0,sys.argv[1]); from contracts import verify; p=verify(json.load(sys.stdin),os.environ['INTERVIEW_WORKER_SIGNING_KEY']); print(p['source_revision'])"
    output, errors, status = Open3.capture3({ "INTERVIEW_WORKER_SIGNING_KEY" => ENV.fetch("INTERVIEW_WORKER_SIGNING_KEY") }, "python3", "-c", code, worker_path, stdin_data: JSON.generate(envelope))
    assert status.success?, errors
    assert_equal record["revision"], output.strip
  end
end
