ActiveRecord::Schema.define do
  create_table :invoices, force: true do |t|
    t.integer :organization_id, null: false
    t.integer :amount_cents, null: false
    t.integer :version, null: false, default: 0
    t.string :status, null: false, default: "draft"
  end
  create_table :invoice_amendments, force: true do |t|
    t.integer :invoice_id, null: false
    t.integer :version, null: false
    t.integer :old_amount_cents, null: false
    t.integer :new_amount_cents, null: false
  end
  # Add database integrity guarantees here.
end
