class ProgressController < ApplicationController
  def show
    MockInterview.where(account: current_account).where.not(status: "completed").find_each { |mock| MockInterviewWorkflow.sync!(mock) }
    current_account.interview_sessions.where(status: "active").where("deadline_at <= ?", Time.current).find_each(&:expire!)
    FollowupWorkflow.expire_scope!(FollowupRound.joins(:interview_session).where(interview_sessions: { account_id: current_account.id }))
    render json: ProgressOverview.call(current_account)
  end
end
