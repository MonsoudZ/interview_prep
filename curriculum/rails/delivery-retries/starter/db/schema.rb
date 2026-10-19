ActiveRecord::Schema[8.1].define(version: 1) do
  create_table :deliveries, force: true do |t|
    t.text :payload, null: false
    t.string :status, null: false, default: "pending"
    t.integer :attempts, null: false, default: 0
    t.integer :last_http_status
    t.string :last_error
  end
end
