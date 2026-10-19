require "test_helper"
require "open3"

class RailwayExecutionTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
    load Rails.root.join("db/seeds.rb")
    @original_signing = ENV["INTERVIEW_WORKER_SIGNING_KEY"]
    ENV["INTERVIEW_WORKER_SIGNING_KEY"] = "s" * 40
    @account = Account.create!(name: "Execution fixture", email: "execution@example.test", password: "execution-password-123")
    @record = @account.interview_sessions.create!(exercise_version: ExerciseVersion.find_by!(track: "rails"), mode: "guided")
    Workspace.save!(@record, { "app/controllers/events_controller.rb" => "# café 🧪\n" })
  end

  teardown { ENV["INTERVIEW_WORKER_SIGNING_KEY"] = @original_signing }

  def execution(status, output, purpose = "tests")
    @record.execution_requests.create!(source_snapshot: @record.current_snapshot, purpose: purpose,
      status: status, client_request_id: SecureRandom.uuid, result: { output: output, runtime_provider: "railway_sandbox" })
  end

  test "Ruby issued jobs verify with the real Node Railway worker contract" do
    request = execution("queued", "")
    path = Rails.root.join("../../services/railway_worker/contract.mjs").expand_path.to_s
    code = 'import {pathToFileURL} from "node:url"; const {verify}=await import(pathToFileURL(process.argv[1])); let raw=""; for await (const chunk of process.stdin) raw+=chunk; console.log(verify(JSON.parse(raw),process.env.INTERVIEW_WORKER_SIGNING_KEY).source_revision);'
    output, errors, status = Open3.capture3({ "INTERVIEW_WORKER_SIGNING_KEY" => ENV.fetch("INTERVIEW_WORKER_SIGNING_KEY") },
      "node", "--input-type=module", "-e", code, path, stdin_data: JSON.generate(WorkerJobs.envelope(request)))
    assert status.success?, errors
    assert_equal @record.current_revision, output.strip
  end

  test "presentation reports starter failures and reference counts with explicit provenance" do
    starter = execution("execution_failed", "12 runs, 12 assertions, 12 failures, 0 errors, 0 skips\n")
    reference = execution("execution_completed", "12 runs, 158 assertions, 0 failures, 0 errors, 0 skips\n")
    assert_equal 0, ExecutionEvidence.summary(starter)[:passed]
    assert_equal 12, ExecutionEvidence.summary(reference)[:passed]
    assert_equal 158, ExecutionEvidence.summary(reference)[:assertions]
    assert_equal true, ExecutionEvidence.summary(reference)[:reported]
    presented = SessionPresenter.call(@record)[:executions]
    assert presented.all? { |item| item[:reported_test_summary][:reported] }
    assert presented.all? { |item| item[:result]["runtime_provider"] == "railway_sandbox" }
  end

  test "infrastructure timeout incomplete and preparation output cannot masquerade as a complete suite" do
    %w[infrastructure_error timed_out output_limit queued leased].each do |status|
      assert_nil ExecutionEvidence.summary(execution(status, "12 runs, 158 assertions, 0 failures, 0 errors, 0 skips"))
    end
    assert_nil ExecutionEvidence.summary(execution("execution_completed", "READY", "prepare"))
    assert_nil ExecutionEvidence.summary(execution("execution_failed", "SyntaxError before test runner started"))
    assert_nil ExecutionEvidence.summary(execution("execution_completed", "12 runs, 1 assertions, 13 failures, 0 errors, 0 skips"))
    assert_nil ExecutionEvidence.summary(execution("execution_completed", "1 runs, 1 assertions, 0 failures, 0 errors, 0 skips"))
  end

  test "execution evidence retains the exact saved revision after further editing" do
    original = execution("execution_completed", "12 runs, 158 assertions, 0 failures, 0 errors, 0 skips")
    Workspace.save!(@record, { "app/controllers/events_controller.rb" => "# changed later\n" })
    presented = SessionPresenter.call(@record)
    refute_equal presented[:revision], presented[:executions].first[:revision]
    assert_equal original.source_snapshot.revision, presented[:executions].first[:revision]
  end
end
