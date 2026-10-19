class MockInterviewsController < ApplicationController
  rescue_from SessionCommandError do |error|
    render json: { error: error.message }, status: error.status
  end
  def index
    records = MockInterview.where(account: current_account).order(created_at: :desc).limit(30)
    render json: { plans: MockInterviewWorkflow.plans, interviews: records.map { |item| MockInterviewWorkflow.sync!(item); item.slice(:id, :title, :status, :stage_index, :deadline_at, :created_at) } }
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
