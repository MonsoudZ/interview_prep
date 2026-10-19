require "test_helper"

class EventsTest < ActionDispatch::IntegrationTest
  def payload(**changes)
    { event_type: "push", actor_id: 11, repository_id: 7,
      occurred_at: "2026-10-16T10:00:00-06:00" }.merge(changes)
  end

  def create_event(**changes)
    post "/events", params: { event: payload(**changes) }, as: :json
    assert_response :created
    response.parsed_body
  end

  def assert_error(status)
    assert_response status
    errors = response.parsed_body.fetch("errors")
    assert errors.is_a?(Hash) && !errors.empty?
    assert errors.values.all? { |messages| messages.is_a?(Array) && !messages.empty? }
  end

  test "creates a persisted event with exact JSON fields" do
    event = create_event
    assert_equal %w[actor_id event_type id occurred_at repository_id], event.keys.sort
    assert_equal "2026-10-16T16:00:00.000Z", event["occurred_at"]
    assert_equal 11, event["actor_id"]
    get "/events/#{event.fetch('id')}"
    assert_response :ok
    assert_equal event, response.parsed_body
  end

  test "rejects missing fields and malformed envelopes without persistence" do
    [{}, { event: nil }, { event: [] }, { event: "bad" }, { event: {} }].each do |body|
      post "/events", params: body, as: :json
      assert_error :unprocessable_content
    end
    payload.keys.each do |field|
      post "/events", params: { event: payload.except(field) }, as: :json
      assert_error :unprocessable_content
    end
    get "/events"
    assert_equal [], response.parsed_body
  end

  test "accepts supported types and rejects unsupported types" do
    %w[push pull_request issue].each { |type| create_event(event_type: type) }
    ["other", "", 7, []].each do |type|
      post "/events", params: { event: payload(event_type: type) }, as: :json
      assert_error :unprocessable_content
    end
    get "/events"
    assert_equal 3, response.parsed_body.length
  end

  test "requires positive integer JSON identifiers" do
    [:actor_id, :repository_id].each do |field|
      [0, -1, 1.5, "7", true, nil].each do |value|
        post "/events", params: { event: payload(**{field => value}) }, as: :json
        assert_error :unprocessable_content
      end
    end
    get "/events"
    assert_equal [], response.parsed_body
  end

  test "rejects timestamps without timezone or with invalid calendar dates" do
    ["bad", "2026-10-16T10:00:00", "2026-02-30T10:00:00Z", nil, 42].each do |stamp|
      post "/events", params: { event: payload(occurred_at: stamp) }, as: :json
      assert_error :unprocessable_content
    end
  end

  test "lists empty events" do
    get "/events"
    assert_response :ok
    assert_equal [], response.parsed_body
  end

  test "lists ascending by generated ID" do
    events = [create_event, create_event(event_type: "issue")]
    get "/events"
    assert_response :ok
    assert_equal events, response.parsed_body
  end

  test "retrieves the requested event" do
    create_event
    selected = create_event(repository_id: 8)
    get "/events/#{selected.fetch('id')}"
    assert_response :ok
    assert_equal selected, response.parsed_body
  end

  test "returns not found for missing or invalid IDs" do
    ["999", "0", "-1", "abc", "1x"].each do |id|
      get "/events/#{id}"
      assert_error :not_found
    end
  end

  test "filters matching repository in ascending order" do
    first = create_event
    create_event(repository_id: 8)
    last = create_event
    get "/events", params: { repository_id: "7" }
    assert_response :ok
    assert_equal [first, last], response.parsed_body
  end

  test "returns empty array for unmatched repository" do
    create_event
    get "/events", params: { repository_id: "99" }
    assert_response :ok
    assert_equal [], response.parsed_body
  end

  test "handles invalid filters malformed JSON and protected fields" do
    ["", "abc", "0", "-1", "7x", "1.5"].each do |filter|
      get "/events", params: { repository_id: filter }
      assert_error :bad_request
    end
    event = create_event(id: 900, unknown: "ignored")
    refute_equal 900, event["id"]
    post "/events", params: '{"event":', headers: { "CONTENT_TYPE" => "application/json" }
    assert_error :bad_request
  end
end
