require "test_helper"

class RubyCurriculumTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
    load Rails.root.join("db/seeds.rb")
    post "/api/register", params: { name: "Ruby curriculum", email: "ruby-curriculum@example.test", password: "testing-password-123" }, as: :json
    assert_response :ok
  end
  test "manifest-published Ruby exercises run through the practice loop without leaking hidden tests or references" do
    entries = RailsCurriculum.entries("ruby")
    assert_equal %w[build-order lru-cache rate-limiter], entries.map { |entry| entry.fetch("slug") }.sort
    get "/api/exercises"
    catalog = response.parsed_body.fetch("exercises")
    entries.each do |entry|
      exercise = ExerciseVersion.find_by!(slug: entry.fetch("slug"), version: entry.fetch("version"))
      root = Rails.root.join("../../curriculum/ruby", entry.fetch("slug"))
      visible = exercise.starter_files.fetch("test/visible_test.rb").scan(/^  def test_/).length
      hidden = root.join("hidden_test.rb").read.scan(/^  def test_/).length
      assert_equal entry.fetch("test_count"), visible + hidden
      assert_equal entry.fetch("test_count"), ExecutionEvidence.expected_tests(exercise)
      assert_equal entry.fetch("operation"), exercise.operation
      assert_includes WorkerJobs::OPERATIONS, entry.fetch("operation")
      assert_includes WorkerJobs::OPERATIONS, WorkerJobs.prepare_operation(entry.fetch("operation"))
      assert exercise.starter_files.keys.none? { |path| path.include?("hidden") || path.include?("reference") }
      public_entry = catalog.find { |item| item["id"] == exercise.id }
      assert public_entry["executable"]
      assert_includes public_entry["tools"], "Isolated Ruby runner"
      post "/api/sessions", params: { exercise_id: exercise.id, mode: "guided" }, as: :json
      assert_response :created
      session = response.parsed_body
      assert_equal ["solution.rb"], session.fetch("editable_paths")
      assert_equal "solution.rb", session.fetch("initial_path")
      assert_includes session.fetch("files").keys, "test/visible_test.rb"
      get "/api/sessions/#{session['id']}/practice"
      assert_response :ok
      assert_equal JSON.parse(root.join("review.json").read).fetch("version"), response.parsed_body.fetch("content_version")
      assert_equal 3, response.parsed_body.fetch("total_hints")
      put "/api/sessions/#{session['id']}/snapshot", params: { expected_revision: session.fetch("revision"), files: { "solution.rb" => "# edit", "test/visible_test.rb" => "# overwrite" } }, as: :json
      assert_response :unprocessable_content
      post "/api/sessions/#{session['id']}/start", as: :json
      assert_response :ok
      post "/api/sessions/#{session['id']}/submit", params: { expected_revision: session.fetch("revision") }, as: :json
      assert_response :ok
      get "/api/sessions/#{session['id']}/review"
      assert_response :ok
      review = response.parsed_body
      assert_operator review.fetch("criteria").length, :>=, 4
      assert review.fetch("reference_available")
      get "/api/sessions/#{session['id']}/reference"
      assert_response :ok
      assert_equal ["solution.rb"], response.parsed_body.fetch("files").keys
    end
  end
  test "a superseded LRU version stays readable from its archived manifest while new sessions get the clarified contract" do
    current = RailsCurriculum.find("lru-cache", 2)
    archived = RailsCurriculum.find("lru-cache", 1)
    assert_equal 2, current.fetch("version")
    assert_equal current.fetch("operation"), archived.fetch("operation"), "the runner and tests did not change"
    assert_equal current.fetch("test_count"), archived.fetch("test_count")
    assert_equal %w[lru-cache], RailsCurriculum.archived.map { |entry| entry.fetch("slug") }
    assert_nil ExerciseVersion.find_by(slug: "lru-cache", version: 1), "fresh seeds publish only the current version"
    archive = Rails.root.join("../../curriculum/ruby/lru-cache/versions/1")
    latest = ExerciseVersion.find_by!(slug: "lru-cache", version: 2)
    assert_includes latest.brief, "Callers cannot tell a stored `nil` from an absent key through `get`"
    refute_includes archive.join("BRIEF.md").read, "Callers cannot tell"
    older = ExerciseVersion.create!(latest.attributes.except("id", "created_at", "updated_at").merge("version" => 1, "brief" => archive.join("BRIEF.md").read))
    assert_equal "ruby-lru-cache-review-v1", RailsCurriculum.review(older).fetch("version")
    assert_equal "ruby-lru-cache-review-v2", RailsCurriculum.review(latest).fetch("version")
    assert_equal "Why must `get` distinguish a stored `nil` from an absent key, and how does your code do that?",
      RailsCurriculum.review(older).fetch("criteria").find { |c| c["id"] == "boundaries" }.fetch("probe")
    assert_match(/without a sentinel/, RailsCurriculum.review(latest).fetch("criteria").find { |c| c["id"] == "boundaries" }.fetch("probe"))
    assert_equal RailsCurriculum.reference(latest), RailsCurriculum.reference(older)
    assert_equal 12, ExecutionEvidence.expected_tests(older)
    assert_equal ExerciseCatalog.details(latest).except(:brief), ExerciseCatalog.details(older).except(:brief)
    get "/api/exercises"
    listed = response.parsed_body.fetch("exercises").select { |item| item["slug"] == "lru-cache" }
    assert_equal [2], listed.map { |item| item["version"] }, "new session selection shows only the latest version"
  end
end
