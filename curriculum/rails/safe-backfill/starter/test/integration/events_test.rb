require "test_helper"
class SafeBackfillTest < ActionDispatch::IntegrationTest
  setup do
    @a = Customer.create!(organization_id: 7, email: " A@Example.COM ")
    @b = Customer.create!(organization_id: 7, email: "B@example.com")
  end
  def run_batch(after_id: 0, through_id: Customer.maximum(:id), batch_size: 10)
    CustomerEmailBackfill.call(after_id: after_id, through_id: through_id, batch_size: batch_size)
  end
  test "normalizes while preserving legacy and exact result shape" do
    result = run_batch
    assert_equal({ cursor: @b.id, scanned: 2, updated: 2, conflicts: 0, done: true }, result)
    assert_equal "a@example.com", @a.reload.normalized_email; assert_equal " A@Example.COM ", @a.email
  end
  test "cursor resumes in small ordered batches including exact final page" do
    result = run_batch(batch_size: 1)
    assert_equal({ cursor: @a.id, scanned: 1, updated: 1, conflicts: 0, done: false }, result)
    result = run_batch(after_id: result[:cursor], batch_size: 1)
    assert_equal({ cursor: @b.id, scanned: 1, updated: 1, conflicts: 0, done: true }, result)
  end
  test "retry preserves newer normalized values and still advances" do
    @a.update!(normalized_email: "new@example.com")
    result = run_batch(batch_size: 1)
    assert_equal @a.id, result[:cursor]; assert_equal 1, result[:scanned]; assert_equal 0, result[:updated]
    assert_equal "new@example.com", @a.reload.normalized_email
    run_batch; assert_equal 0, run_batch[:updated]
  end
  test "fixed high water ignores newly inserted records" do
    high = @b.id
    later = Customer.create!(organization_id: 7, email: "later@example.com")
    assert run_batch(through_id: high)[:done]; assert_nil later.reload.normalized_email
  end
  test "blank emails advance without inventing addresses" do
    @a.update!(email: nil); @b.update!(email: "  ")
    result = run_batch; assert_equal 0, result[:updated]; assert result[:done]
    assert_nil @a.reload.normalized_email; assert_nil @b.reload.normalized_email
  end
  test "duplicates conflict within tenant but not across tenants" do
    @b.update!(email: "a@example.com")
    other = Customer.create!(organization_id: 8, email: "A@example.com")
    result = run_batch
    assert_equal 2, result[:updated]; assert_equal 1, result[:conflicts]; assert result[:done]
    assert_nil @b.reload.normalized_email; assert_equal "a@example.com", other.reload.normalized_email
  end
  test "database enforces tenant uniqueness and permits multiple NULLs" do
    @a.update!(normalized_email: "same@example.com")
    assert_raises(ActiveRecord::RecordNotUnique) { @b.update_columns(normalized_email: "same@example.com") }
    Customer.create!(organization_id: 8, normalized_email: "same@example.com")
    Customer.create!(organization_id: 7); Customer.create!(organization_id: 7)
  end
  test "invalid arguments and empty windows" do
    [[-1, 3, 1], [2, 1, 1], [0, 2, 0], [0, 2, 101], ["0", 2, 1], [0, 2, 1.5]].each do |a, h, size|
      assert_raises(ArgumentError) { run_batch(after_id: a, through_id: h, batch_size: size) }
    end
    assert_equal({ cursor: @b.id, scanned: 0, updated: 0, conflicts: 0, done: true }, run_batch(after_id: @b.id))
  end
  test "read fallback and normalized preference never write on GET" do
    get "/customers/#{@a.id}", headers: { "X-Organization-ID" => "7" }; assert_response :ok
    assert_equal({ "id" => @a.id, "email" => "a@example.com" }, response.parsed_body); assert_nil @a.reload.normalized_email
    @a.update!(normalized_email: "preferred@example.com")
    get "/customers/#{@a.id}", headers: { "X-Organization-ID" => "7" }; assert_response :ok
    assert_equal "preferred@example.com", response.parsed_body["email"]
  end
  test "read identity and foreign customer are protected" do
    ["", "0", "7oops"].each { |id| get "/customers/#{@a.id}", headers: { "X-Organization-ID" => id }; assert_response :unauthorized }
    get "/customers/#{@a.id}", headers: { "X-Organization-ID" => "8" }; assert_response :not_found
  end
  test "batch loading is bounded in SQL" do
    150.times { |i| Customer.create!(organization_id: 7, email: "u#{i}@example.com") }
    records = 0
    subscriber = ->(*args) { records += args.last[:record_count] if args.last[:class_name] == "Customer" }
    result = nil
    ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") { result = run_batch(batch_size: 3) }
    assert_equal 3, result[:scanned]; assert_operator records, :<=, 3
  end
  test "interleaved dual writes and legacy edits are preserved" do
    first_id, second_id = @a.id, @b.id
    intercepted = false
    callback = proc do |record|
      unless intercepted
        intercepted = true
        Customer.where(id: first_id).update_all(normalized_email: "fresh@example.com")
        Customer.where(id: second_id).update_all(email: "changed@example.com")
      end
    end
    Customer.set_callback(:find, :after, callback)
    result = run_batch
    assert intercepted, "Backfill must read a bounded batch of customer rows"
    assert_equal "fresh@example.com", @a.reload.normalized_email
    assert_equal "changed@example.com", @b.reload.email
    refute_equal "b@example.com", @b.normalized_email, "Never persist a value derived from stale legacy data"
    assert_operator result[:updated], :<=, 1
  ensure
    Customer.skip_callback(:find, :after, callback) if callback
  end
end
