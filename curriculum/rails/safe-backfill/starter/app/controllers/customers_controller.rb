class CustomersController < ApplicationController
  def show
    customer = Customer.find(params[:id])
    render json: { id: customer.id, email: customer.email }
  end
end
