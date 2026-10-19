require "test_helper"

class RubyExecutionTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
    load Rails.root.join("db/seeds.rb")
    post "/api/register", params: { name: "Ruby practice", email: "ruby-runner@example.test", password: "testing-password-123" }, as: :json
    assert_response :ok
  end
  test "latest catalog selects executable Ruby while preserving the older writing version" do
    get "/api/exercises"
    versions = response.parsed_body.fetch("exercises").select { |e| e["slug"] == "merge-intervals" }
    assert_equal 1, versions.length
    exercise = versions.sole
    assert_equal 2, exercise.fetch("version")
    assert exercise.fetch("executable")
    refute exercise.key?("limitation")
    assert_nil ExerciseVersion.find_by!(slug: "merge-intervals", version: 1).operation
    post "/api/sessions", params: { exercise_id: exercise.fetch("id"), mode: "guided" }, as: :json
    assert_response :created
    session = response.parsed_body
    assert_equal ["solution.rb"], session.fetch("editable_paths")
    assert_includes session.fetch("files").keys, "test/visible_test.rb"
    refute session.fetch("files").keys.any? { |path| path.include?("hidden") || path.include?("reference") }
    get "/api/sessions/#{session['id']}/practice"
    assert_response :ok
    assert_equal "ruby-intervals-review-v2", response.parsed_body.fetch("content_version")
    put "/api/sessions/#{session['id']}/snapshot", params: { expected_revision: session.fetch("revision"), files: { "solution.rb" => "# unchanged", "test/visible_test.rb" => "# overwrite" } }, as: :json
    assert_response :unprocessable_content
  end
end
