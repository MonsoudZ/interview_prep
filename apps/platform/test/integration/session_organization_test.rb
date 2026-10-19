require "test_helper"
class SessionOrganizationTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
    load Rails.root.join("db/seeds.rb")
    post "/api/register", params: { name: "Organization fixture", email: "organize@example.test", password: "organization-fixture-password" }, as: :json
    assert_response :ok
    @account = Account.find_by!(email: "organize@example.test")
  end
  def body = response.parsed_body
  def submitted
    exercise = ExerciseVersion.find_by!(slug: "merge-intervals", version: 2)
    session = @account.interview_sessions.create!(exercise_version: exercise, mode: "guided")
    Workspace.save!(session, {"solution.rb" => "# Synthetic archive verification\ndef merge_intervals(input)\n  input\nend\n"})
    session.update!(status: "submitted", submitted_revision: session.current_revision, submitted_at: Time.current)
    session
  end
  def mock_interview
    post "/api/mock_interviews", params: {plan_key: "debugging",client_request_id: SecureRandom.uuid}, as: :json
    assert_response :created
    MockInterview.find(body.fetch("id"))
  end
  test "archive and restore hide completed sessions without changing immutable work or reviews" do
    session = submitted
    content = PracticeContent.for(session.exercise_version)
    criterion = content.fetch("criteria").first
    session.create_session_review!(source_snapshot: session.current_snapshot, content_version: content.fetch("version"), entries: {
      criterion.fetch("id") => {"rating"=>"needs_development","notes"=>"Synthetic fixture", "evidence"=>{"path"=>"solution.rb","start_line"=>1,"end_line"=>2}}
    })
    revision = session.submitted_revision
    files = session.current_snapshot.files
    2.times do
      post "/api/sessions/#{session.id}/archive", as: :json; assert_response :ok
      assert body["archived_at"]
    end
    get "/api/sessions"; assert_response :ok; assert_empty body["sessions"]
    get "/api/sessions?archived=true"; assert_response :ok; assert_equal [session.id], body["sessions"].map {|item| item["id"]}
    get "/api/sessions/#{session.id}/review"; assert_response :ok
    assert_equal "needs_development", body.dig("entries",criterion.fetch("id"),"rating")
    get "/api/progress"; assert_response :ok; assert_equal 1, body.fetch("skills").length
    assert_empty body.fetch("recent_attempts"); assert_empty body.fetch("awaiting_review")
    assert_equal revision, session.reload.submitted_revision; assert_equal files, session.current_snapshot.files
    post "/api/sessions/#{session.id}/restore", as: :json; assert_response :ok; assert_nil body["archived_at"]
    get "/api/sessions"; assert_equal [session.id],body["sessions"].map {|item| item["id"]}
    get "/api/sessions?archived=true"; assert_empty body["sessions"]
  end
  test "unfinished sessions cannot be hidden and archiving never pauses a timer" do
    session = submitted
    session.update!(status: "active", deadline_at: 10.minutes.from_now, submitted_revision:nil,submitted_at:nil)
    deadline = session.deadline_at
    post "/api/sessions/#{session.id}/archive", as: :json; assert_response :conflict
    assert_nil session.reload.archived_at; assert_equal deadline,session.deadline_at
    session.update!(status:"ready",deadline_at:nil)
    post "/api/sessions/#{session.id}/archive", as: :json; assert_response :conflict
    assert_nil session.reload.archived_at
  end
  test "unfinished followups block hiding the source and archived sources reject new rounds" do
    session = submitted
    round,_ = FollowupWorkflow.create!(@account,session,SecureRandom.uuid,"guided")
    post "/api/sessions/#{session.id}/archive", as: :json; assert_response :conflict
    round.update!(status:"completed",completed_at:Time.current,completion_reason:"fixture")
    post "/api/sessions/#{session.id}/archive", as: :json; assert_response :ok
    post "/api/sessions/#{session.id}/followups", params:{client_request_id:SecureRandom.uuid,mode:"guided"},as: :json
    assert_response :conflict
    assert_equal 1,session.followup_rounds.count
  end
  test "mock archive restores all linked stages and child controls cannot split the interview" do
    mock=mock_interview
    child=mock.mock_interview_stages.first.interview_session
    post "/api/mock_interviews/#{mock.id}/archive",as: :json;assert_response :conflict
    MockInterviewWorkflow.command!(mock,{command:"finish",expected_version:mock.reload.lock_version})
    post "/api/sessions/#{child.id}/archive",as: :json;assert_response :conflict
    post "/api/mock_interviews/#{mock.id}/archive",as: :json;assert_response :ok
    assert body["archived_at"];assert child.reload.archived_at
    get "/api/mock_interviews";assert_empty body["interviews"]
    get "/api/mock_interviews?archived=true";assert_equal [mock.id],body["interviews"].map{|item|item["id"]}
    get "/api/sessions";assert_empty body["sessions"]
    post "/api/sessions/#{child.id}/restore",as: :json;assert_response :conflict
    post "/api/mock_interviews/#{mock.id}/restore",as: :json;assert_response :ok
    assert_nil mock.reload.archived_at;assert_nil child.reload.archived_at
    assert_equal child.current_revision,child.submitted_revision
  end
  test "session listing reconciles overdue standalone and mock clocks before reporting status" do
    session=submitted
    session.update!(status:"active",deadline_at:1.second.ago,submitted_revision:nil,submitted_at:nil)
    mock=mock_interview
    mock.update!(status:"active",started_at:1.hour.ago,deadline_at:1.second.ago)
    child=mock.mock_interview_stages.first.interview_session
    get "/api/sessions";assert_response :ok
    assert_equal "submitted",session.reload.status
    assert_equal "submitted",child.reload.status
    assert_equal "completed",mock.reload.status
    assert body["sessions"].all?{|item|item["status"]=="submitted"}
    assert_equal 2,body["total"]
  end
  test "archive endpoints are account scoped and keep source private" do
    session=submitted;mock=mock_interview
    delete "/api/logout",as: :json
    post "/api/sessions/#{session.id}/archive",as: :json;assert_response :unauthorized
    post "/api/register",params:{name:"Other",email:"other-organize@example.test",password:"other-organization-password"},as: :json
    %w[archive restore].each do |action|
      post "/api/sessions/#{session.id}/#{action}",as: :json;assert_response :not_found
      post "/api/mock_interviews/#{mock.id}/#{action}",as: :json;assert_response :not_found
    end
    assert_nil session.reload.archived_at;assert_nil mock.reload.archived_at
  end
  test "Rails tasks open their relevant source file without rewriting published exercises" do
    {"tenant-projects"=>"projects_controller.rb","idempotent-checkout"=>"orders_controller.rb","delivery-retries"=>"delivery_job.rb","activity-feed"=>"feed_controller.rb"}.each do |slug, filename|
      exercise=ExerciseVersion.find_by!(slug:slug,version:1)
      post "/api/sessions",params:{exercise_id:exercise.id,mode:"guided"},as: :json
      assert_response :created
      assert body.fetch("initial_path").end_with?(filename)
      assert body.fetch("editable_paths").include?(body.fetch("initial_path"))
    end
  end
end
