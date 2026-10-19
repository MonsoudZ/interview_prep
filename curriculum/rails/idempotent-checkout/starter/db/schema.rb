ActiveRecord::Schema[8.1].define(version: 1) do
  create_table :products, force: true do |t|
    t.string :name, null: false
    t.integer :stock, null: false
  end
  create_table :orders, force: true do |t|
    t.integer :customer_id, null: false
    t.string :idempotency_key, null: false
    t.integer :product_id, null: false
    t.integer :quantity, null: false
  end
  # TODO: enforce the published uniqueness and check constraints.
end
