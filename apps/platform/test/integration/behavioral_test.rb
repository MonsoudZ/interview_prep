require "test_helper"

class BehavioralTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
    load Rails.root.join("db/seeds.rb")
    post "/api/register", params: { name: "Behavioral fixture", email: "behavioral@example.test", password: "behavioral-test-password" }, as: :json
    assert_response :ok
    @account = Account.find_by!(email: "behavioral@example.test")
    @exercise = ExerciseVersion.find_by!(slug: "behavioral-ownership")
  end
  def body = response.parsed_body
  def attributes
    { title: "Synthetic incident example", topics: %w[ownership incidents], readiness: "draft",
      sections: BehavioralContent::SECTIONS.to_h { |key| [key, "Fixture #{key}"] } }
  end
  def story
    @story ||= BehavioralStories.create!(@account, SecureRandom.uuid, attributes.deep_stringify_keys)
  end
  def update_story(command, **extra)
    patch "/api/stories/#{story.id}", params: { command: command, expected_version: story.reload.lock_version }.merge(extra), as: :json
  end
  def rehearse(request_id = SecureRandom.uuid, version = story.reload.lock_version)
    post "/api/stories/#{story.id}/rehearse", params: { exercise_id: @exercise.id, client_request_id: request_id, expected_version: version }, as: :json
  end
  test "five published themes have writing workspaces and answer evidence" do
    exercises = ExerciseVersion.where(track: "behavioral")
    assert_equal 5, exercises.count
    exercises.each do |exercise|
      assert_nil exercise.operation
      assert_equal %w[answer.md preparation.md], exercise.starter_files.keys.sort
      assert_equal ["answer.md"], PracticeContent.for(exercise).fetch("evidence_paths")
      assert_equal 4, PracticeContent.for(exercise).fetch("criteria").length
    end
    get "/api/stories"; assert_response :ok
    assert_equal 5, body.fetch("exercises").length
  end
  test "creation retries deduplicate and invalid or incomplete stories are rejected" do
    id = SecureRandom.uuid
    2.times do
      post "/api/stories", params: { client_request_id: id, story: attributes }, as: :json
      assert_response :created
    end
    assert_equal 1, BehavioralStory.where(account: @account).count
    [attributes.merge(topics: ["unknown"]), attributes.merge(sections: {}), attributes.merge(title: " "),
      attributes.merge(sections: attributes[:sections].merge("actions" => "x" * 6001)),
      attributes.merge(sections: BehavioralContent::SECTIONS.to_h { |key| [key, "界" * 3000] }),
      attributes.merge(readiness: "ready", sections: attributes[:sections].merge("actions" => ""))].each do |invalid|
      post "/api/stories", params: { client_request_id: SecureRandom.uuid, story: invalid }, as: :json
      assert_response :unprocessable_content
    end
  end
  test "stale writes preserve saved text and archives are reversible" do
    version = story.lock_version
    update_story("save", story: attributes.merge(title: "Saved title")); assert_response :ok
    patch "/api/stories/#{story.id}", params: { command: "save", expected_version: version, story: attributes }, as: :json
    assert_response :conflict
    assert_equal "Saved title", story.reload.title
    update_story("archive"); assert_response :ok
    get "/api/stories"; assert_empty body.fetch("stories")
    get "/api/stories?archived=true"; assert_equal [story.id], body.fetch("stories").map { |s| s["id"] }
    update_story("save", story: attributes); assert_response :conflict
    rehearse; assert_response :conflict
    update_story("restore"); assert_response :ok
    assert_nil story.reload.archived_at
  end
  test "all story endpoints and direct rehearsal service enforce ownership" do
    story
    post "/api/register", params: { name: "Other", email: "other@example.test", password: "behavioral-test-password" }, as: :json
    other = Account.find_by!(email: "other@example.test")
    get "/api/stories/#{story.id}"; assert_response :not_found
    update_story("archive"); assert_response :not_found
    rehearse; assert_response :not_found
    assert_raises(ActiveRecord::RecordNotFound) { BehavioralStories.rehearse!(other, story, @exercise.id, SecureRandom.uuid, story.lock_version) }
  end
  test "rehearsals capture immutable preparation and retries return the original session" do
    request_id = SecureRandom.uuid
    rehearse(request_id); assert_response :created
    record = InterviewSession.find(body.fetch("id"))
    original = record.current_snapshot.files.fetch("preparation.md")
    assert_includes original, "Fixture actions"
    assert_equal "guided", record.mode
    assert_equal story.id, record.behavioral_context.fetch("story_id")
    update_story("save", story: attributes.merge(sections: attributes[:sections].merge("actions" => "Later edit"))); assert_response :ok
    rehearse(request_id, 0); assert_response :created
    assert_equal record.id, body.fetch("id")
    assert_equal original, record.reload.current_snapshot.files.fetch("preparation.md")
    rehearse(SecureRandom.uuid, 0); assert_response :conflict
    post "/api/sessions/#{record.id}/execute", params: { client_request_id: SecureRandom.uuid, purpose: "tests" }, as: :json
    assert_response :unprocessable_content
    assert_empty record.execution_requests
  end
  test "timed answers lock until start expire and only answer lines count as evidence" do
    post "/api/sessions", params: { exercise_id: @exercise.id, mode: "assessment" }, as: :json
    assert_response :created
    record = InterviewSession.find(body.fetch("id"))
    files = record.current_snapshot.files.merge("answer.md" => "Synthetic practiced answer.\n")
    put "/api/sessions/#{record.id}/snapshot", params: { expected_revision: record.current_revision, files: files }, as: :json
    assert_response :conflict
    post "/api/sessions/#{record.id}/start", as: :json; assert_response :ok
    put "/api/sessions/#{record.id}/snapshot", params: { expected_revision: record.reload.current_revision, files: files }, as: :json
    assert_response :ok
    travel_to record.reload.deadline_at + 1.second do
      get "/api/sessions/#{record.id}"; assert_response :ok
      assert_equal "submitted", record.reload.status
    end
    get "/api/sessions/#{record.id}/review"; assert_response :ok
    assert_equal ["answer.md"], body.fetch("evidence_files")
    entry = { rating: "meets_target", notes: "Synthetic review fixture", evidence: { path: "preparation.md", start_line: 1, end_line: 1 } }
    put "/api/sessions/#{record.id}/review", params: { expected_version: nil, entries: { clarity: entry }, reflection: "" }, as: :json
    assert_response :unprocessable_content
    entry[:evidence][:path] = "answer.md"
    put "/api/sessions/#{record.id}/review", params: { expected_version: nil, entries: { clarity: entry }, reflection: "" }, as: :json
    assert_response :ok
    assert_equal "Synthetic practiced answer.\n", body.dig("entries", "clarity", "evidence", "excerpt")
    post "/api/sessions/#{record.id}/automated_review", params: { client_request_id: SecureRandom.uuid }, as: :json
    assert_response :conflict
  end
  test "rehearsal quotas reject new work while allowing retries and reworks retain provenance" do
    rehearse; assert_response :created
    record = InterviewSession.find(body.fetch("id"))
    post "/api/sessions/#{record.id}/start", as: :json; assert_response :ok
    post "/api/sessions/#{record.id}/submit", params: { expected_revision: record.reload.current_revision }, as: :json; assert_response :ok
    post "/api/sessions/#{record.id}/rework", params: { client_request_id: SecureRandom.uuid, mode: "guided", goal: "Make my actions specific", expected_revision: record.reload.submitted_revision }, as: :json
    assert_response :created
    post "/api/sessions/#{record.id}/followups", params: { client_request_id: SecureRandom.uuid, mode: "guided" }, as: :json
    assert_response :created
    assert_equal "Reflection and transfer", FollowupRound.last.questions.last.fetch("title")
    child = @account.interview_sessions.find_by!(revision_of_id: record.id)
    assert_equal record.behavioral_context, child.behavioral_context
    assert_equal record.current_snapshot.files, child.current_snapshot.files
    9.times { @account.interview_sessions.create!(exercise_version: @exercise, mode: "guided") }
    rehearse; assert_response :too_many_requests
    assert_equal 10, @account.interview_sessions.where.not(status: "submitted").count
  end
  test "story limit includes archives and request retries still return existing work" do
    id = story.client_request_id
    99.times { BehavioralStories.create!(@account, SecureRandom.uuid, attributes.deep_stringify_keys) }
    update_story("archive"); assert_response :ok
    post "/api/stories", params: { client_request_id: SecureRandom.uuid, story: attributes }, as: :json
    assert_response :too_many_requests
    post "/api/stories", params: { client_request_id: id, story: attributes }, as: :json
    assert_response :created
    assert_equal story.id, body.fetch("id")
  end

end
