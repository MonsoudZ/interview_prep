class EscalationsController < ApplicationController
  def create
    agent = Agent.find_by(id: request.headers["X-Agent-ID"].to_i)
    ticket = Ticket.find(params[:id])
    reason = params.dig(:escalation, :reason).to_s
    ticket.update!(status: "escalated", reason: reason)
    EscalationAudit.create!(ticket_id: ticket.id, agent_id: agent.id, reason: reason)
    render json: { id: ticket.id, status: ticket.status, reason: reason }
  end
end
