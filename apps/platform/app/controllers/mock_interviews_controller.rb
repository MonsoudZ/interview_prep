class MockInterviewsController < ApplicationController
  rescue_from SessionCommandError do |error|
    render json: { error: error.message }, status: error.status
  end
  def index
    scope = MockInterview.where(account: current_account)
    scope = params[:archived] == "true" ? scope.where.not(archived_at: nil) : scope.where(archived_at: nil)
    records = scope.order(created_at: :desc, id: :desc).limit(30)
    render json: { total: scope.count, limit: 30, plans: MockInterviewWorkflow.plans, interviews: records.map { |item| MockInterviewWorkflow.sync!(item); item.slice(:id, :title, :status, :stage_index, :deadline_at, :created_at, :archived_at) } }
  end
  def archive
    render json: MockInterviewWorkflow.present(SessionOrganization.archive_interview!(owned))
  end
  def restore
    render json: MockInterviewWorkflow.present(SessionOrganization.archive_interview!(owned, restore: true))
  end
  def create
    record = MockInterviewWorkflow.create!(current_account, params[:plan_key], params[:client_request_id])
    render json: MockInterviewWorkflow.present(record), status: :created
  end
  def show
    render json: MockInterviewWorkflow.present(owned)
  end
  def update
    render json: MockInterviewWorkflow.present(MockInterviewWorkflow.command!(owned, params))
  end
  private
  def owned
    @owned ||= MockInterview.where(account: current_account).find(params[:id])
  end
end
