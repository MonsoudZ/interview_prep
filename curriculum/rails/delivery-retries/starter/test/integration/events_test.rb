require "test_helper"
class DeliveryRetriesTest < ActiveSupport::TestCase
  setup do
    @delivery = Delivery.create!(payload: '{"event":"push"}')
    @calls = 0
  end
  def transport(code = 200, exception: nil)
    original = DeliveryTransport.method(:deliver)
    owner = self
    DeliveryTransport.define_singleton_method(:deliver) do |delivery|
      owner.instance_variable_set(:@calls, owner.instance_variable_get(:@calls) + 1)
      raise exception if exception
      code
    end
    yield
  ensure
    DeliveryTransport.define_singleton_method(:deliver, original) if original
  end
  def run_job
    DeliveryJob.perform_now(@delivery.id)
  end
  test "success marks delivered and clears earlier error" do
    @delivery.update!(last_error: "Earlier failure")
    transport(201) { run_job }
    assert_equal ["delivered", 1, 201, nil], @delivery.reload.attributes.values_at("status", "attempts", "last_http_status", "last_error")
    assert_equal 1, @calls
  end
  test "all successful status boundaries are accepted" do
    [200, 204, 299].each do |code|
      @delivery.update!(status: "pending", attempts: 0)
      transport(code) { run_job }
      assert_equal "delivered", @delivery.reload.status
    end
  end
  test "delivered duplicates do not send or increment" do
    @delivery.update!(status: "delivered", attempts: 1, last_http_status: 200)
    transport { 2.times { run_job } }
    assert_equal 0, @calls; assert_equal 1, @delivery.reload.attempts
  end
  test "ordinary client errors are terminal" do
    [400, 401, 404, 499].each do |code|
      @delivery.update!(status: "pending", attempts: 0)
      transport(code) { run_job }
      assert_equal "failed", @delivery.reload.status; assert_equal code, @delivery.last_http_status
      assert @delivery.last_error.present?
    end
  end
  test "rate limiting is transient" do
    transport(429) { assert_raises(DeliveryJob::Retryable) { run_job } }
    assert_equal ["pending", 1, 429], @delivery.reload.attributes.values_at("status", "attempts", "last_http_status")
    assert @delivery.last_error.present?
  end
  test "server errors and redirects are transient" do
    [300, 302, 500, 503, 599].each do |code|
      @delivery.update!(status: "pending", attempts: 0)
      transport(code) { assert_raises(DeliveryJob::Retryable) { run_job } }
      assert_equal "pending", @delivery.reload.status; assert_equal 1, @delivery.attempts
      assert_equal code, @delivery.last_http_status
    end
  end
  test "unavailable clears stale HTTP status and records a durable attempt" do
    @delivery.update!(last_http_status: 503)
    transport(exception: DeliveryTransport::Unavailable) { assert_raises(DeliveryJob::Retryable) { run_job } }
    assert_equal ["pending", 1, nil], @delivery.reload.attributes.values_at("status", "attempts", "last_http_status")
    assert @delivery.last_error.present?
  end
  test "third transient attempt is terminal without raising retryable" do
    transport(503) do
      2.times { assert_raises(DeliveryJob::Retryable) { run_job } }
      run_job
    end
    assert_equal ["failed", 3, 503], @delivery.reload.attributes.values_at("status", "attempts", "last_http_status")
    assert_equal 3, @calls
  end
  test "success after retry preserves total attempts and payload" do
    transport(503) { assert_raises(DeliveryJob::Retryable) { run_job } }
    transport(200) { run_job }
    assert_equal ["delivered", 2, nil], @delivery.reload.attributes.values_at("status", "attempts", "last_error")
    assert_equal '{"event":"push"}', @delivery.payload
  end
  test "missing and permanently failed jobs do not call transport" do
    @delivery.update!(status: "failed", attempts: 3, last_error: "Exhausted")
    transport do
      run_job
      DeliveryJob.perform_now(99999)
    end
    assert_equal 0, @calls; assert_equal 3, @delivery.reload.attempts
    assert_equal "Exhausted", @delivery.last_error
  end
  test "programming errors propagate without recording fake delivery outcomes" do
    transport(exception: ArgumentError) { assert_raises(ArgumentError) { run_job } }
    assert_equal 0, @delivery.reload.attempts; assert_equal "pending", @delivery.status
  end
  test "transport outages also exhaust after exactly three calls" do
    transport(exception: DeliveryTransport::Unavailable) do
      2.times { assert_raises(DeliveryJob::Retryable) { run_job } }
      run_job
      run_job
    end
    assert_equal "failed", @delivery.reload.status; assert_equal 3, @delivery.attempts
    assert_equal 3, @calls; assert_nil @delivery.last_http_status
  end
end
