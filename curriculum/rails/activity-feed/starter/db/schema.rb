ActiveRecord::Schema[8.1].define(version: 1) do
  create_table :authors, force: true do |t|
    t.string :name, null: false
  end
  create_table :posts, force: true do |t|
    t.integer :organization_id, null: false
    t.integer :author_id, null: false
    t.text :body, null: false
  end
  create_table :comments, force: true do |t|
    t.integer :post_id, null: false
    t.text :body, null: false
  end
end
