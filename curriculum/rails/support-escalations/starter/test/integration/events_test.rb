require "test_helper"
class EscalationTest < ActionDispatch::IntegrationTest
  setup do
    @supervisor = Agent.create!(organization_id: 7, role: "supervisor")
    @agent = Agent.create!(organization_id: 7, role: "agent")
    @ticket = Ticket.create!(organization_id: 7, subject: "Cannot sign in")
  end
  def escalate(agent: @supervisor.id.to_s, ticket: @ticket.id, body: { escalation: { reason: "  Needs specialist help  " } })
    post "/tickets/#{ticket}/escalate", params: body, headers: { "X-Agent-ID" => agent }, as: :json
  end
  def error(status)
    assert_response status
    assert response.parsed_body.fetch("errors").values.all? { |v| v.is_a?(Array) && v.any? }
  end
  test "exact response and persisted trimmed reason" do
    escalate; assert_response :ok
    assert_equal({ "id" => @ticket.id, "status" => "escalated", "reason" => "Needs specialist help" }, response.parsed_body)
    assert_equal "Needs specialist help", @ticket.reload.reason
    assert_equal "Cannot sign in", @ticket.subject
  end
  test "one audit binds actual agent ticket and reason" do
    escalate; assert_response :ok
    audit = EscalationAudit.sole
    assert_equal [@ticket.id, @supervisor.id, "Needs specialist help"], audit.attributes.values_at("ticket_id", "agent_id", "reason")
  end
  test "identity is strict and cannot be supplied in body" do
    ["", "0", "-1", "1oops", "999999"].each do |id|
      escalate(agent: id, body: { agent_id: @supervisor.id, escalation: { reason: "Needs specialist help" } }); error(:unauthorized)
    end
    assert_equal "open", @ticket.reload.status; assert_equal 0, EscalationAudit.count
  end
  test "foreign and missing tickets are hidden" do
    other = Ticket.create!(organization_id: 8)
    escalate(ticket: other.id); error(:not_found)
    escalate(ticket: 999999); error(:not_found)
    assert_equal "open", other.reload.status
  end
  test "ordinary agents cannot escalate local tickets" do
    escalate(agent: @agent.id.to_s); error(:forbidden)
    assert_equal "open", @ticket.reload.status; assert_equal 0, EscalationAudit.count
  end
  test "foreign ticket lookup precedes role check" do
    other = Ticket.create!(organization_id: 8)
    escalate(agent: @agent.id.to_s, ticket: other.id); error(:not_found)
  end
  test "duplicate escalation returns conflict with one audit" do
    escalate; assert_response :ok
    escalate; error(:conflict)
    assert_equal 1, EscalationAudit.count
  end
  test "closed tickets cannot be escalated" do
    @ticket.update!(status: "closed")
    escalate; error(:conflict); assert_equal "closed", @ticket.reload.status
  end
  test "malformed envelopes are rejected without writes" do
    [{}, { escalation: [] }, { escalation: "bad" }, { escalation: {} }, { escalation: { reason: 12 } }].each { |body| escalate(body: body); error(:unprocessable_content) }
    assert_equal "open", @ticket.reload.status; assert_equal 0, EscalationAudit.count
  end
  test "reason length uses trimmed characters and accepts boundaries" do
    [" " * 20, "x" * 9, "x" * 201].each { |reason| escalate(body: { escalation: { reason: reason } }); error(:unprocessable_content) }
    [10, 200].each do |length|
      ticket = Ticket.create!(organization_id: 7)
      escalate(ticket: ticket.id, body: { escalation: { reason: "é" * length } }); assert_response :ok
      assert_equal length, ticket.reload.reason.length
    end
  end
  test "unknown attributes cannot change ownership or audit identity" do
    escalate(body: { escalation: { reason: "Needs specialist help", organization_id: 8, status: "closed", agent_id: @agent.id } })
    assert_response :ok; assert_equal 7, @ticket.reload.organization_id; assert_equal @supervisor.id, EscalationAudit.sole.agent_id
  end
  test "audit failure rolls back the ticket and propagates" do
    original = EscalationAudit.method(:create!)
    EscalationAudit.define_singleton_method(:create!) { |*| raise ActiveRecord::StatementInvalid, "simulated audit failure" }
    assert_raises(ActiveRecord::StatementInvalid) { escalate }
    assert_equal "open", @ticket.reload.status; assert_nil @ticket.reason; assert_equal 0, EscalationAudit.count
  ensure
    EscalationAudit.define_singleton_method(:create!, original) if original
  end
end
