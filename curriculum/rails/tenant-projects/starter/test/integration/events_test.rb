require "test_helper"
class TenantProjectsTest < ActionDispatch::IntegrationTest
  setup do
    @editor = User.create!(organization_id: 10, api_token: "editor-token", role: "editor")
    @viewer = User.create!(organization_id: 10, api_token: "viewer-token", role: "viewer")
    @own = Project.create!(organization_id: 10, name: "Alpha")
    @other = Project.create!(organization_id: 20, name: "Private")
  end
  def headers(token = "editor-token")
    { "Authorization" => "Bearer #{token}" }
  end
  def error(status)
    assert_response status
    assert_match(/json/, response.media_type)
    body = response.parsed_body.fetch("errors")
    assert body.is_a?(Hash) && body.any?
    assert body.values.all? { |v| v.is_a?(Array) && v.any? }
  end
  test "authentication is required on every action" do
    get "/projects"; error(:unauthorized)
    get "/projects/#{@own.id}"; error(:unauthorized)
    patch "/projects/#{@own.id}", params: { project: { name: "Bad" } }, as: :json
    error(:unauthorized)
    assert_equal "Alpha", @own.reload.name
  end
  test "unknown and malformed tokens are rejected" do
    ["Bearer unknown", "Basic editor-token", "Bearer", "Bearer editor-token extra"].each do |token|
      get "/projects", headers: { "Authorization" => token }; error(:unauthorized)
    end
  end
  test "listing uses authenticated tenant and deterministic ordering" do
    second = Project.create!(organization_id: 10, name: "Beta")
    get "/projects?organization_id=20", headers: headers
    assert_response :ok
    assert_equal [@own.id, second.id], response.parsed_body.map { |p| p.fetch("id") }
    assert_equal %w[id name organization_id], response.parsed_body.first.keys.sort
  end
  test "empty tenant listing is an array" do
    User.create!(organization_id: 30, api_token: "empty", role: "viewer")
    get "/projects", headers: headers("empty"); assert_response :ok
    assert_equal [], response.parsed_body
  end
  test "own lookup has exact fields" do
    get "/projects/#{@own.id}", headers: headers; assert_response :ok
    assert_equal({ "id" => @own.id, "name" => "Alpha", "organization_id" => 10 }, response.parsed_body)
  end
  test "cross tenant and malformed lookups are concealed" do
    [@other.id, 99999, "1oops", "0", "-1"].each do |id|
      get "/projects/#{id}", headers: headers; error(:not_found)
    end
  end
  test "editor can update own project" do
    patch "/projects/#{@own.id}", params: { project: { name: "Renamed" } }, headers: headers, as: :json
    assert_response :ok
    assert_equal "Renamed", @own.reload.name
    assert_equal %w[id name organization_id], response.parsed_body.keys.sort
  end
  test "viewer cannot update own project" do
    patch "/projects/#{@own.id}", params: { project: { name: "Bad" } }, headers: headers("viewer-token"), as: :json
    error(:forbidden); assert_equal "Alpha", @own.reload.name
  end
  test "all roles get not found for cross tenant updates" do
    ["editor-token", "viewer-token"].each do |token|
      patch "/projects/#{@other.id}", params: { project: { name: "Bad" } }, headers: headers(token), as: :json
      error(:not_found)
    end
    assert_equal "Private", @other.reload.name
  end
  test "invalid names and envelopes never persist" do
    [{}, { project: [] }, { project: "bad" }, { project: {} }, *[nil, "", "   ", 7, "x" * 81].map { |name| { project: { name: name } } }].each do |input|
      patch "/projects/#{@own.id}", params: input, headers: headers, as: :json
      error(:unprocessable_content); assert_equal "Alpha", @own.reload.name
    end
  end
  test "tenant and primary key cannot be reassigned" do
    patch "/projects/#{@own.id}", params: { project: { name: "Safe", organization_id: 20, id: 123456 } }, headers: headers, as: :json
    assert_response :ok
    assert_equal 10, @own.reload.organization_id
    assert_equal "Safe", @own.name
    assert_equal 2, Project.count
  end
  test "maximum length is accepted and malformed update IDs are not coerced" do
    patch "/projects/#{@own.id}", params: { project: { name: "x" * 80 } }, headers: headers, as: :json
    assert_response :ok
    patch "/projects/#{@own.id}oops", params: { project: { name: "Bad" } }, headers: headers, as: :json
    error(:not_found); assert_equal "x" * 80, @own.reload.name
  end
end
