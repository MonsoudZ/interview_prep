ActiveRecord::Schema.define do
  create_table :customers, force: true do |t|
    t.integer :organization_id, null: false
    t.string :email
    t.string :normalized_email
  end
  add_index :customers, [:organization_id, :normalized_email], unique: true
end
