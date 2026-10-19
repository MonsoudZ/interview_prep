class EscalationsController < ApplicationController
  def create
    identity = request.headers["X-Agent-ID"].to_s
    agent = Agent.find_by(id: identity.to_i) if identity.match?(/\A[1-9]\d*\z/)
    return problem(:unauthorized, "agent", "Invalid identity") unless agent
    ticket = Ticket.find_by(id: params[:id], organization_id: agent.organization_id)
    return problem(:not_found, "ticket", "Not found") unless ticket
    return problem(:forbidden, "agent", "Supervisor required") unless agent.role == "supervisor"
    envelope = params[:escalation]
    reason = envelope[:reason] if envelope.is_a?(ActionController::Parameters)
    unless reason.is_a?(String) && reason.strip.length.between?(10, 200)
      return problem(:unprocessable_content, "reason", "Use 10–200 characters")
    end
    reason = reason.strip
    ticket.with_lock do
      return problem(:conflict, "ticket", "Ticket is not open") unless ticket.status == "open"
      ticket.update!(status: "escalated", reason: reason)
      EscalationAudit.create!(ticket_id: ticket.id, agent_id: agent.id, reason: reason)
    end
    render json: { id: ticket.id, status: ticket.status, reason: ticket.reason }
  end
  private
  def problem(status, field, message)
    render json: { errors: { field => [message] } }, status: status
  end
end
