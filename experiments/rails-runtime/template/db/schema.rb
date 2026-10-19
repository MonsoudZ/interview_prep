ActiveRecord::Schema[8.1].define(version: 1) do
  create_table :events, force: true do |t|
    t.string :event_type, null: false
    t.integer :actor_id, null: false
    t.integer :repository_id, null: false
    t.datetime :occurred_at, null: false
  end
end
