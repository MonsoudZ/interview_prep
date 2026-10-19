ActiveRecord::Schema[8.1].define(version: 1) do
  create_table :products, force: true do |t|
    t.string :name, null: false
    t.integer :stock, null: false
    t.check_constraint "stock >= 0", name: "nonnegative_stock"
  end
  create_table :orders, force: true do |t|
    t.integer :customer_id, null: false
    t.string :idempotency_key, null: false
    t.integer :product_id, null: false
    t.integer :quantity, null: false
    t.check_constraint "quantity > 0", name: "positive_quantity"
  end
  add_index :orders, [:customer_id, :idempotency_key], unique: true
end
