require "test_helper"
class AutomatedReviewsTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
    load Rails.root.join("db/seeds.rb")
    @old_key=ENV["INTERVIEW_REVIEW_BRIDGE_KEY"]
    ENV["INTERVIEW_REVIEW_BRIDGE_KEY"]="r"*40
    post "/api/register",params:{name:"Review transport",email:"review@example.test",password:"testing-password-123"},as: :json
    assert_response :ok
    @worker=SecureRandom.uuid
    @model="transport-fixture"
    @digest="sha256:"+"a"*64
  end
  teardown { ENV["INTERVIEW_REVIEW_BRIDGE_KEY"]=@old_key }
  def body = response.parsed_body
  def submission(slug="merge-intervals",version=2)
    exercise=ExerciseVersion.find_by!(slug:slug,version:version)
    post "/api/sessions",params:{exercise_id:exercise.id,mode:"guided"},as: :json
    assert_response :created
    record=body
    post "/api/sessions/#{record['id']}/start",as: :json;assert_response :ok
    post "/api/sessions/#{record['id']}/submit",params:{expected_revision:record['revision']},as: :json;assert_response :ok
    record
  end
  def worker_post(path,data)
    post "/internal/reviews/#{path}",params:data,as: :json,headers:{"Authorization"=>"Bearer #{ENV.fetch('INTERVIEW_REVIEW_BRIDGE_KEY')}"}
    body
  end
  def connect
    worker_post("heartbeat",{worker_id:@worker,model:@model,model_digest:@digest});assert_response :ok
  end
  def request_review(record,id=SecureRandom.uuid)
    post "/api/sessions/#{record['id']}/automated_review",params:{client_request_id:id},as: :json
    body
  end
  def lease
    leased=worker_post("lease",{worker_id:@worker});assert_response :ok
    leased
  end
  def report_for(leased)
    packet=leased.fetch("job").fetch("input")
    {"summary"=>"Synthetic transport fixture; not an actual model-quality result.",
      "criteria"=>packet.fetch("rubric").map{|c|{"id"=>c.fetch("id"),"rating"=>"not_observed","reasoning"=>"Transport test makes no judgment.","evidence"=>[]}},
      "findings"=>[],"strengths"=>[],"understanding_checks"=>["Explain a boundary case."],"limitations"=>["Synthetic callback fixture."]}
  end
  def deliver(leased,report=report_for(leased),extra={})
    job=leased.fetch("job")
    post "/internal/reviews/#{job.fetch('id')}/result",params:{lease_token:leased.fetch("lease_token"),revision:job.fetch("revision"),prompt_version:job.fetch("prompt_version"),model:@model,model_digest:@digest,status:"completed",report:report,usage:{input_tokens:10,output_tokens:20,duration_seconds:1.0}}.merge(extra),as: :json,headers:{"Authorization"=>"Bearer #{ENV.fetch('INTERVIEW_REVIEW_BRIDGE_KEY')}"}
  end
  test "offline workers cannot create a misleading review or queue and owner boundaries apply" do
    record=submission
    request_review(record);assert_response :service_unavailable
    assert_equal 0,AutomatedReview.count
    get "/api/sessions/#{record['id']}/automated_review";assert_response :ok
    refute body.fetch("available");assert_nil body.fetch("review")
    delete "/api/logout",as: :json
    get "/api/sessions/#{record['id']}/automated_review";assert_response :unauthorized
    post "/api/register",params:{name:"Other",email:"other-review@example.test",password:"testing-password-123"},as: :json
    get "/api/sessions/#{record['id']}/automated_review";assert_response :not_found
    request_review(record);assert_response :not_found
  end
  test "reviews bind source rubric model and assistance without changing self assessments" do
    record=submission;connect
    key=SecureRandom.uuid
    queued=request_review(record,key);assert_response :accepted
    assert_equal "queued",queued.fetch("review").fetch("status")
    refute queued.fetch("review").key?("lease_digest")
    request_review(record,key);assert_response :accepted
    request_review(record);assert_response :accepted
    assert_equal 1,AutomatedReview.count
    leased=lease
    assert_nil lease.fetch("job")
    packet=leased.fetch("job").fetch("input")
    assert_equal record.fetch("revision"),packet.fetch("revision")
    assert_equal ["solution.rb"],packet.fetch("files").keys
    refute packet.key?("account")
    assert_equal "guided",packet.fetch("mode")
    report=report_for(leased)
    report["criteria"][0].merge!("rating"=>"needs_development","reasoning"=>"The implementation remains a placeholder.","evidence"=>[{"path"=>"solution.rb","start_line"=>1,"end_line"=>3}])
    deliver(leased,report);assert_response :ok
    get "/api/sessions/#{record['id']}/automated_review";assert_response :ok
    result=body.fetch("review")
    assert_equal "completed",result.fetch("status")
    assert_equal @digest,result.fetch("model_digest")
    assert_includes result.fetch("report").fetch("criteria")[0].fetch("evidence")[0].fetch("excerpt"),"Implement the published contract"
    assert_equal 0,SessionReview.count
    deliver(leased,report_for(leased));assert_response :ok
    assert_equal "needs_development",AutomatedReview.sole.report.fetch("criteria")[0].fetch("rating")
    request_review(record);assert_response :accepted
    assert_equal 1,AutomatedReview.count
  end
  test "draft reviews are blocked and queue capacity applies across submissions" do
    connect
    records=3.times.map{submission}
    records.first(2).each{|record|request_review(record);assert_response :accepted}
    request_review(records.last);assert_response :too_many_requests
    exercise=ExerciseVersion.find_by!(slug:"merge-intervals",version:2)
    post "/api/sessions",params:{exercise_id:exercise.id,mode:"guided"},as: :json
    request_review(body);assert_response :conflict
  end
  test "unknown locations rubric ids and fabricated execution evidence reject the whole report" do
    record=submission;connect
    mutations=[
      ->(r){r["criteria"][0]["id"]="imaginary"},
      ->(r){r["criteria"][0].merge!("rating"=>"meets_target","evidence"=>[])},
      ->(r){r["criteria"][0]["evidence"]=[{"path"=>"reference/solution.rb","start_line"=>1,"end_line"=>1}]},
      ->(r){r["criteria"][0]["evidence"]=[{"path"=>"solution.rb","start_line"=>0,"end_line"=>99}]},
      ->(r){r["findings"]=[{"severity"=>"major","category"=>"execution_observation","title"=>"Claim","observation"=>"Claim","consequence"=>"Claim","recommendation"=>"Claim","confidence"=>"high","evidence"=>[{"path"=>"solution.rb","start_line"=>1,"end_line"=>1}],"execution_ids"=>[SecureRandom.uuid]}]}
    ]
    mutations.each do |mutate|
      request_review(record);assert_response :accepted
      leased=lease;report=report_for(leased);mutate.call(report)
      deliver(leased,report);assert_response :ok
      result=AutomatedReview.order(created_at: :desc).first
      assert_equal "failed",result.status;assert_equal "output_invalid",result.error_code;assert_nil result.report
    end
  end
  test "bad leases and wrong revision cannot replace a running review and expired work is not revived" do
    record=submission;connect;request_review(record);leased=lease
    deliver(leased,report_for(leased),{lease_token:"bad"});assert_response :unauthorized
    deliver(leased,report_for(leased),{revision:"wrong"});assert_response :conflict
    assert_equal "running",AutomatedReview.sole.status
    travel 7.minutes do
      get "/api/sessions/#{record['id']}/automated_review";assert_response :ok
      assert_equal "failed",body.fetch("review").fetch("status")
      deliver(leased);assert_response :ok
      assert_nil AutomatedReview.sole.report
    end
  end
  test "review packets support all tracks and omit runs from other revisions" do
    %w[repository-events merge-intervals webhook-delivery].each do |slug|
      record=submission(slug,slug=="repository-events"?1:2)
      session=InterviewSession.find(record['id'])
      old=session.source_snapshots.create!(revision:"old-#{slug}",files:{"notes.md"=>"old"})
      session.execution_requests.create!(source_snapshot:old,purpose:"tests",client_request_id:SecureRandom.uuid,status:"execution_failed",result:{"output"=>"Different source"})
      packet=ReviewPacket.build(session)
      assert_equal record['revision'],packet.fetch("revision")
      assert_equal [],packet.fetch("executions")
      refute packet.fetch("rubric").empty?
    end
  end
  test "review gateway has a separate authentication secret" do
    post "/internal/reviews/heartbeat",params:{worker_id:@worker,model:@model,model_digest:@digest},as: :json
    assert_response :unauthorized
    worker_post("heartbeat",{worker_id:@worker,model:"bad model",model_digest:@digest});assert_response :unprocessable_content
  end
end
