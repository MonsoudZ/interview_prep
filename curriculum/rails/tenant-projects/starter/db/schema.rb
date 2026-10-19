ActiveRecord::Schema[8.1].define(version: 1) do
  create_table :users, force: true do |t|
    t.integer :organization_id, null: false
    t.string :api_token, null: false
    t.string :role, null: false
  end
  add_index :users, :api_token, unique: true
  create_table :projects, force: true do |t|
    t.integer :organization_id, null: false
    t.string :name, null: false
  end
end
