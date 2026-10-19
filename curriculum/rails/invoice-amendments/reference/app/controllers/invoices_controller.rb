class InvoicesController < ApplicationController
  def update
    organization = request.headers["X-Organization-ID"].to_s
    return problem(:unauthorized, "identity") unless organization.match?(/\A[1-9]\d*\z/)
    invoice = Invoice.find_by(id: params[:id], organization_id: organization.to_i)
    return problem(:not_found, "invoice") unless invoice
    input = params[:invoice]
    amount, version = input.values_at(:amount_cents, :expected_version) if input.is_a?(ActionController::Parameters)
    unless amount.is_a?(Integer) && amount.between?(1, 100_000_000) && version.is_a?(Integer) && version >= 0
      return problem(:unprocessable_content, "invoice")
    end
    changed = false
    Invoice.transaction do
      # Both the read used for audit evidence and conditional write are inside the transaction.
      invoice.reload
      if invoice.status == "draft" && invoice.version == version
        changed = Invoice.where(id: invoice.id, organization_id: organization.to_i, status: "draft", version: version)
          .update_all(amount_cents: amount, version: version + 1) == 1
        if changed
          InvoiceAmendment.create!(invoice_id: invoice.id, version: version + 1,
            old_amount_cents: invoice.amount_cents, new_amount_cents: amount)
        end
      end
    end
    return problem(:conflict, "version") unless changed
    render json: { id: invoice.id, amount_cents: amount, version: version + 1 }
  end
  private
  def problem(status, field)
    render json: { errors: { field => ["Request could not be applied"] } }, status: status
  end
end
