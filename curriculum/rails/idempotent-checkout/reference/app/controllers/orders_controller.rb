class OrdersController < ApplicationController
  def create
    customer = request.headers["X-Customer-ID"].to_s
    return failure(:unauthorized, "Customer required") unless customer.match?(/\A[1-9][0-9]*\z/)
    key = request.headers["Idempotency-Key"].to_s
    return failure(:bad_request, "Invalid key") unless key.match?(/\A[A-Za-z0-9_-]{1,64}\z/)
    input = params[:order]
    unless input.is_a?(ActionController::Parameters) && [:product_id, :quantity].all? { |k| input[k].is_a?(Integer) && input[k] > 0 }
      return failure(:unprocessable_content, "Invalid order")
    end
    customer_id = customer.to_i
    Product.transaction do
      existing = Order.find_by(customer_id: customer_id, idempotency_key: key)
      if existing
        if existing.product_id == input[:product_id] && existing.quantity == input[:quantity]
          render json: serialize(existing), status: :ok
        else
          failure(:conflict, "Key already used with different order")
        end
        return
      end
      product = Product.lock.find_by(id: input[:product_id])
      return failure(:not_found, "Product not found") unless product
      changed = Product.where(id: product.id).where("stock >= ?", input[:quantity]).update_all(["stock = stock - ?", input[:quantity]])
      return failure(:conflict, "Insufficient stock") unless changed == 1
      order = Order.create!(customer_id: customer_id, idempotency_key: key, product_id: product.id, quantity: input[:quantity])
      render json: serialize(order), status: :created
    end
  end
  private
  def serialize(order)
    order.as_json(only: [:id, :customer_id, :product_id, :quantity])
  end
  def failure(status, message)
    render json: { errors: { base: [message] } }, status: status
  end
end
