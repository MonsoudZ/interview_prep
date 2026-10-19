ActiveRecord::Schema.define do
  create_table :agents, force: true do |t|
    t.integer :organization_id, null: false
    t.string :role, null: false
  end
  create_table :tickets, force: true do |t|
    t.integer :organization_id, null: false
    t.string :status, null: false, default: "open"
    t.string :reason
    t.string :subject
  end
  create_table :escalation_audits, force: true do |t|
    t.integer :ticket_id, null: false
    t.integer :agent_id, null: false
    t.string :reason, null: false
  end
  add_index :escalation_audits, :ticket_id, unique: true
end
