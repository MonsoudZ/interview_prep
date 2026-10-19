require "test_helper"
class InvoiceAmendmentsTest < ActionDispatch::IntegrationTest
  setup { @invoice = Invoice.create!(organization_id: 7, amount_cents: 1000) }
  def amend(amount: 2500, version: 0, organization: "7", id: @invoice.id, body: nil)
    patch "/invoices/#{id}", params: body || { invoice: { amount_cents: amount, expected_version: version } }, headers: { "X-Organization-ID" => organization }, as: :json
  end
  def error(status)
    assert_response status
    assert response.parsed_body.fetch("errors").values.all? { |v| v.is_a?(Array) && v.any? }
  end
  test "success changes amount and increments revision" do
    amend; assert_response :ok
    assert_equal({ "id" => @invoice.id, "amount_cents" => 2500, "version" => 1 }, response.parsed_body)
    assert_equal [2500, 1], @invoice.reload.attributes.values_at("amount_cents", "version")
  end
  test "audit records old new and committed version" do
    amend; assert_response :ok
    assert_equal [@invoice.id, 1, 1000, 2500], InvoiceAmendment.sole.attributes.values_at("invoice_id", "version", "old_amount_cents", "new_amount_cents")
  end
  test "stale tab cannot overwrite a newer value" do
    amend; assert_response :ok
    amend(amount: 9999); error(:conflict)
    assert_equal [2500, 1], @invoice.reload.attributes.values_at("amount_cents", "version"); assert_equal 1, InvoiceAmendment.count
  end
  test "next revision and unchanged amount still append history" do
    amend; assert_response :ok
    amend(amount: 2500, version: 1); assert_response :ok
    assert_equal 2, @invoice.reload.version; assert_equal [1, 2], InvoiceAmendment.order(:version).pluck(:version)
  end
  test "paid invoices reject changes" do
    @invoice.update!(status: "paid")
    amend; error(:conflict); assert_equal 1000, @invoice.reload.amount_cents; assert_equal 0, InvoiceAmendment.count
  end
  test "strict identity and tenant lookup" do
    ["", "0", "7oops", "-1"].each { |org| amend(organization: org); error(:unauthorized) }
    amend(organization: "8"); error(:not_found)
    amend(id: 999999); error(:not_found)
  end
  test "amount and version require bounded JSON integers" do
    [0, -1, 100_000_001, "2", 1.5, nil, true].each { |value| amend(amount: value); error(:unprocessable_content) }
    [-1, "0", nil, true, 0.5].each { |value| amend(version: value); error(:unprocessable_content) }
    assert_equal 1000, @invoice.reload.amount_cents; assert_equal 0, InvoiceAmendment.count
  end
  test "malformed envelopes and future versions" do
    [{}, { invoice: [] }, { invoice: "bad" }, { invoice: {} }].each { |body| amend(body: body); error(:unprocessable_content) }
    amend(version: 999); error(:conflict)
  end
  test "client attributes cannot change organization status or version directly" do
    amend(body: { invoice: { amount_cents: 1, expected_version: 0, organization_id: 8, status: "paid", version: 900 } })
    assert_response :ok; assert_equal [7, "draft", 1, 1], @invoice.reload.attributes.values_at("organization_id", "status", "version", "amount_cents")
  end
  test "database prevents duplicate amendment revisions" do
    attrs = { invoice_id: @invoice.id, version: 1, old_amount_cents: 1000, new_amount_cents: 2000 }
    InvoiceAmendment.insert_all!([attrs])
    assert_raises(ActiveRecord::RecordNotUnique) { InvoiceAmendment.insert_all!([attrs]) }
    InvoiceAmendment.insert_all!([attrs.merge(version: 2)]); assert_equal 2, InvoiceAmendment.count
  end
  test "database rejects nonpositive amounts without model validation" do
    assert_raises(ActiveRecord::StatementInvalid) { @invoice.update_columns(amount_cents: 0) }
    assert_raises(ActiveRecord::StatementInvalid) { @invoice.update_columns(amount_cents: -1) }
  end
  test "audit failure rolls back amount and revision" do
    original = InvoiceAmendment.method(:create!)
    InvoiceAmendment.define_singleton_method(:create!) { |*| raise ActiveRecord::StatementInvalid, "simulated audit failure" }
    assert_raises(ActiveRecord::StatementInvalid) { amend }
    assert_equal [1000, 0], @invoice.reload.attributes.values_at("amount_cents", "version"); assert_equal 0, InvoiceAmendment.count
  ensure
    InvoiceAmendment.define_singleton_method(:create!, original) if original
  end
end
