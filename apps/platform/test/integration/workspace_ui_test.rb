require "test_helper"

class WorkspaceUiTest < ActionDispatch::IntegrationTest
  test "editor style nonce matches a strict uncached document policy and changes on refresh" do
    get "/"
    assert_response :ok
    nonce = response.body[/name="style-nonce" content="([^"]+)"/, 1]
    assert nonce.present?
    policy = response.headers.fetch("Content-Security-Policy")
    assert_includes policy, "style-src 'self' 'nonce-#{nonce}'"
    assert_includes policy, "script-src 'self';"
    refute_includes policy, "unsafe-inline"
    assert_equal "no-store", response.headers["Cache-Control"]
    get "/"
    refute_equal nonce, response.body[/name="style-nonce" content="([^"]+)"/, 1]
    get "/index.html"
    assert_response :not_found
  end

  test "exercise previews expose editorial level and real tools without source solutions" do
    Rails.cache.clear
    load Rails.root.join("db/seeds.rb")
    post "/api/register", params: {name: "Preview",email: "catalog@example.test",password: "testing-password-123"},as: :json
    assert_response :ok
    get "/api/exercises"
    assert_response :ok
    items=response.parsed_body.fetch("exercises")
    rails=items.find { |item| item["slug"]=="repository-events" }
    assert_equal "Senior · implementation", rails["difficulty"]
    assert_includes rails["tools"], "12 integration tests"
    assert_includes rails["brief"], "POST /events"
    refute rails.key?("starter_files")
    items.reject { |item| item["executable"] }.each do |item|
      refute_includes item["tools"], "Isolated Rails runner"
      assert item["limitation"].present?
    end
  end
end
