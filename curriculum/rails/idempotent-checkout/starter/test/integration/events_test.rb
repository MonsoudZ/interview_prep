require "test_helper"
class CheckoutTest < ActionDispatch::IntegrationTest
  setup { @product = Product.create!(name: "Keyboard", stock: 5) }
  def checkout(key: "request-1", customer: "7", product: @product.id, quantity: 2, body: nil)
    post "/orders", params: body || { order: { product_id: product, quantity: quantity } },
      headers: { "X-Customer-ID" => customer, "Idempotency-Key" => key }, as: :json
  end
  def error(status)
    assert_response status
    errors = response.parsed_body.fetch("errors")
    assert errors.is_a?(Hash) && errors.any?
    assert errors.values.all? { |v| v.is_a?(Array) && v.any? }
  end
  test "first success persists exact response and deducts stock" do
    checkout; assert_response :created
    assert_equal %w[customer_id id product_id quantity], response.parsed_body.keys.sort
    assert_equal 7, response.parsed_body["customer_id"]
    assert_equal 2, Order.sole.quantity
    assert_equal 3, @product.reload.stock
  end
  test "same key replays original response without another deduction" do
    checkout; first = response.parsed_body
    checkout; assert_response :ok
    assert_equal first, response.parsed_body
    assert_equal 1, Order.count; assert_equal 3, @product.reload.stock
  end
  test "replay succeeds after inventory is exhausted" do
    checkout(quantity: 5); assert_response :created
    first = response.parsed_body
    checkout(quantity: 5); assert_response :ok
    assert_equal first, response.parsed_body; assert_equal 0, @product.reload.stock
  end
  test "changed payload conflicts without side effects" do
    checkout; assert_response :created
    checkout(quantity: 1); error(:conflict)
    other = Product.create!(name: "Other", stock: 10)
    checkout(product: other.id); error(:conflict)
    assert_equal 1, Order.count; assert_equal 3, @product.reload.stock; assert_equal 10, other.reload.stock
  end
  test "keys are scoped to the authenticated customer" do
    checkout; assert_response :created
    checkout(customer: "8"); assert_response :created
    assert_equal [7, 8], Order.order(:id).pluck(:customer_id); assert_equal 1, @product.reload.stock
  end
  test "insufficient inventory and unknown products do not reserve keys" do
    checkout(quantity: 6); error(:conflict); assert_equal 0, Order.count
    @product.update!(stock: 10)
    checkout(quantity: 6); assert_response :created
    checkout(key: "missing", product: 99999); error(:not_found)
    assert_equal 1, Order.count
  end
  test "identity and idempotency key are strict" do
    ["", "7oops", "0", "-1"].each { |v| checkout(customer: v); error(:unauthorized) }
    ["", "a b", "a" * 65].each { |v| checkout(key: v); error(:bad_request) }
    assert_equal 0, Order.count; assert_equal 5, @product.reload.stock
  end
  test "only positive JSON integers are accepted" do
    [0, -1, "2", 1.5, true, nil].each do |value|
      checkout(quantity: value); error(:unprocessable_content)
      checkout(product: value); error(:unprocessable_content)
    end
    assert_equal 0, Order.count; assert_equal 5, @product.reload.stock
  end
  test "malformed envelopes and unknown attributes" do
    [{}, { order: [] }, { order: "bad" }, { order: {} }].each { |body| checkout(body: body); error(:unprocessable_content) }
    checkout(body: { order: { product_id: @product.id, quantity: 1, customer_id: 99, id: 999 } })
    assert_response :created; assert_equal 7, Order.sole.customer_id; assert_not_equal 999, Order.sole.id
  end
  test "database uniqueness protects key scope independently of model validation" do
    attrs = { customer_id: 7, idempotency_key: "db-key", product_id: @product.id, quantity: 1 }
    Order.insert_all!([attrs])
    assert_raises(ActiveRecord::RecordNotUnique) { Order.insert_all!([attrs]) }
    Order.insert_all!([attrs.merge(customer_id: 8)])
    assert_equal 2, Order.count
  end
  test "database constraints prevent negative stock and nonpositive quantity" do
    assert_raises(ActiveRecord::StatementInvalid) { @product.update_columns(stock: -1) }
    assert_raises(ActiveRecord::StatementInvalid) do
      Order.insert_all!([{ customer_id: 7, idempotency_key: "invalid", product_id: @product.id, quantity: 0 }])
    end
  end
  test "unexpected persistence failure rolls back the stock decrement" do
    original = Order.method(:create!)
    Order.define_singleton_method(:create!) { |*| raise ActiveRecord::StatementInvalid, "simulated storage failure" }
    assert_raises(ActiveRecord::StatementInvalid) { checkout }
    assert_equal 5, @product.reload.stock; assert_equal 0, Order.count
  ensure
    Order.define_singleton_method(:create!, original) if original
  end
end
