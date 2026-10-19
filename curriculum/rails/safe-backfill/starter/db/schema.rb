ActiveRecord::Schema.define do
  create_table :customers, force: true do |t|
    t.integer :organization_id, null: false
    t.string :email
    t.string :normalized_email
  end
  # Add tenant-scoped uniqueness without making the new column mandatory.
end
