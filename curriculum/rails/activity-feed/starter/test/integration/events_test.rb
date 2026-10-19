require "test_helper"
class ActivityFeedTest < ActionDispatch::IntegrationTest
  setup do
    @author = Author.create!(name: "Avery")
    @posts = 12.times.map { |i| Post.create!(organization_id: 7, author: @author, body: "Post #{i}") }
    Post.create!(organization_id: 8, author: @author, body: "Private")
    3.times { Comment.create!(post: @posts.last, body: "Comment") }
  end
  def feed(query = "", organization: "7")
    get "/feed#{query}", headers: { "X-Organization-ID" => organization }
  end
  def items
    response.parsed_body.fetch("items")
  end
  def error(status)
    assert_response status
    errors = response.parsed_body.fetch("errors")
    assert errors.is_a?(Hash) && errors.any?
    assert errors.values.all? { |v| v.is_a?(Array) && v.any? }
  end
  test "default page returns exact JSON fields and correct values" do
    feed; assert_response :ok
    assert_equal %w[items next_cursor], response.parsed_body.keys.sort
    assert_equal 10, items.length
    assert_equal %w[author_name body comments_count id], items.first.keys.sort
    assert_equal "Avery", items.first["author_name"]
    assert_equal "Post 11", items.first["body"]; assert_equal 3, items.first["comments_count"]
    assert_equal 0, items.last["comments_count"]
  end
  test "descending ordering and tenant scope ignore query identity" do
    feed("?organization_id=8&limit=50"); assert_response :ok
    assert_equal @posts.reverse.map(&:id), items.map { |p| p["id"] }
    assert_nil response.parsed_body["next_cursor"]
  end
  test "missing and malformed identity are rejected" do
    ["", "7oops", "0", "-1"].each { |value| feed(organization: value); error(:unauthorized) }
  end
  test "empty tenant has no next cursor" do
    feed(organization: "99"); assert_response :ok
    assert_equal [], items; assert_nil response.parsed_body["next_cursor"]
  end
  test "cursor traverses stable dataset with no duplicates or omissions" do
    ids = []; query = "?limit=5"
    3.times do
      feed(query); assert_response :ok
      ids.concat(items.map { |p| p["id"] })
      cursor = response.parsed_body["next_cursor"]
      query = "?limit=5&before=#{cursor}"
    end
    assert_equal @posts.reverse.map(&:id), ids
    assert_nil response.parsed_body["next_cursor"]
  end
  test "exact page size has no next cursor" do
    feed("?limit=12"); assert_response :ok
    assert_equal 12, items.length; assert_nil response.parsed_body["next_cursor"]
  end
  test "limit boundaries one and fifty are supported" do
    feed("?limit=1"); assert_response :ok
    assert_equal [@posts.last.id], items.map { |p| p["id"] }
    assert_equal @posts.last.id, response.parsed_body["next_cursor"]
    feed("?limit=50"); assert_response :ok; assert_equal 12, items.length
  end
  test "invalid limit and cursor values are rejected" do
    ["", "0", "-1", "2oops", "1.5"].each do |value|
      feed("?limit=#{value}"); error(:bad_request)
      feed("?before=#{value}"); error(:bad_request)
    end
    feed("?limit=51"); error(:bad_request)
  end
  test "cursor uses strict less than and need not exist" do
    feed("?before=#{@posts[5].id}&limit=50"); assert_response :ok
    assert_equal @posts.first(5).reverse.map(&:id), items.map { |p| p["id"] }
    feed("?before=99999&limit=50"); assert_response :ok; assert_equal 12, items.length
    feed("?before=1"); assert_response :ok; assert_equal [], items
  end
  test "author and counts are correct across multiple authors" do
    other = Author.create!(name: "Blair")
    @posts[10].update!(author: other)
    Comment.create!(post: @posts[10], body: "Only one")
    feed; assert_response :ok
    assert_equal ["Avery", "Blair"], items.first(2).map { |p| p["author_name"] }
    assert_equal [3, 1], items.first(2).map { |p| p["comments_count"] }
  end
  test "queries stay bounded on larger pages" do
    38.times { |i| Post.create!(organization_id: 7, author: Author.create!(name: "Author #{i}"), body: "Large #{i}") }
    queries = []
    subscriber = ->(*args) { event = args.last; sql = event[:sql]; queries << sql if event[:name] != "SCHEMA" && sql.match?(/\ASELECT/i) && sql.match?(/\b(posts|authors|comments)\b/i) }
    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { feed("?limit=50") }
    end
    assert_response :ok; assert_equal 50, items.length
    assert_operator queries.length, :<=, 4, "Expected <=4 data SELECTs; observed #{queries.length}"
  end
  test "database pagination bounds instantiated records even with many comments" do
    188.times { |i| Post.create!(organization_id: 7, author: @author, body: "Extra #{i}") }
    100.times { Comment.create!(post: Post.where(organization_id: 7).last, body: "Many") }
    records = 0
    subscriber = ->(*args) { records += args.last[:record_count] }
    ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") { feed("?limit=50") }
    assert_response :ok; assert_equal 50, items.length
    assert_equal 100, items.first["comments_count"]
    assert_operator records, :<=, 110, "Filter/limit in SQL and aggregate comments; instantiated #{records} records"
  end
end
