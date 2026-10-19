class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
  before_action :require_account
  after_action { response.headers["Cache-Control"] = "no-store" }
  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "Not found" }, status: :not_found
  end
  rescue_from ActiveRecord::RecordInvalid, Workspace::Invalid do |error|
    render json: { error: error.message }, status: :unprocessable_content
  end
  rescue_from ActionController::InvalidAuthenticityToken do
    render json: { error: "Session verification failed. Reload and try again." }, status: :unprocessable_content
  end
  rescue_from ActionController::ParameterMissing do
    render json: { error: "Required request fields are missing" }, status: :bad_request
  end
  rescue_from ActiveRecord::RecordNotUnique, ActiveRecord::StaleObjectError do
    render json: { error: "Concurrent change. Reload before retrying." }, status: :conflict
  end

  private

  def current_account
    return @current_account if defined?(@current_account)
    @current_account = if session[:account_id] && session[:signed_in_at].to_i > 30.days.ago.to_i
      Account.find_by(id: session[:account_id])
    end
  end

  def require_account
    render json: { error: "Sign in to continue" }, status: :unauthorized unless current_account
  end

  def owner_session
    @owner_session ||= current_account.interview_sessions.find(params[:id])
  end
end
