class InvoicesController < ApplicationController
  def update
    invoice = Invoice.find(params[:id])
    invoice.update!(amount_cents: params.dig(:invoice, :amount_cents))
    render json: { id: invoice.id, amount_cents: invoice.amount_cents, version: invoice.version }
  end
end
