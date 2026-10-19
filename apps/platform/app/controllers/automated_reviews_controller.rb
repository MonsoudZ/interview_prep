class AutomatedReviewsController < ApplicationController
  rescue_from SessionCommandError do |error|
    render json: { error: error.message }, status: error.status
  end
  def show
    owner_session.expire!
    return render json: { error: "Submit your work first" }, status: :conflict unless owner_session.status == "submitted"
    render json: AutomatedReviewWorkflow.present(owner_session)
  end
  def create
    AutomatedReviewWorkflow.request!(owner_session, current_account, params[:client_request_id])
    render json: AutomatedReviewWorkflow.present(owner_session), status: :accepted
  end
end
