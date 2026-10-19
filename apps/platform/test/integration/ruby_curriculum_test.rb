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
      exercise = ExerciseVersion.find_by!(slug: entry.fetch("slug"), version: 1)
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
end
