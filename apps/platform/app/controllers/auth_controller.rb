class AuthController < ApplicationController
  skip_before_action :require_account, only: [:bootstrap, :register, :login]
  rate_limit to: 10, within: 3.minutes, only: [:register, :login], with: -> { render json: { error: "Too many attempts. Try again shortly." }, status: :too_many_requests }

  def bootstrap
    render json: { account: current_account&.as_json(only: [:id, :name, :email]),
      csrf_token: form_authenticity_token, registration_allowed: registration_allowed? }
  end

  def register
    return render json: { error: "Registration is disabled" }, status: :forbidden unless registration_allowed?
    account = Account.create!(params.permit(:name, :email, :password, :password_confirmation))
    sign_in(account)
  end

  def login
    account = Account.authenticate_by(email: params[:email].to_s.strip.downcase, password: params[:password].to_s)
    if account
      sign_in(account)
    else
      render json: { error: "Email or password is incorrect" }, status: :unauthorized
    end
  end

  def logout
    reset_session
    render json: { csrf_token: form_authenticity_token }
  end

  private

  def registration_allowed?
    ENV.fetch("ALLOW_REGISTRATION", Rails.env.development? ? "true" : "false") == "true"
  end

  def sign_in(account)
    reset_session
    session[:account_id] = account.id
    session[:signed_in_at] = Time.current.to_i
    render json: { account: account.as_json(only: [:id, :name, :email]), csrf_token: form_authenticity_token }
  end
end
