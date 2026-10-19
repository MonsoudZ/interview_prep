class CustomersController < ApplicationController
  def show
    organization = request.headers["X-Organization-ID"].to_s
    return problem(:unauthorized) unless organization.match?(/\A[1-9]\d*\z/)
    customer = Customer.find_by(id: params[:id], organization_id: organization.to_i)
    return problem(:not_found) unless customer
    render json: { id: customer.id, email: customer.normalized_email.nil? ? customer.email&.strip&.downcase : customer.normalized_email }
  end
  private
  def problem(status)
    render json: { errors: { customer: ["Request could not be read"] } }, status: status
  end
end
