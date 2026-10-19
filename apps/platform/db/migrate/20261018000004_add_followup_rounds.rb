class AddFollowupRounds < ActiveRecord::Migration[8.1]
  def change
    create_table :followup_rounds, id: :string do |t|
      t.references :interview_session, type: :string, null: false, foreign_key: true
      t.references :source_snapshot, type: :string, null: false, foreign_key: true
      t.string :client_request_id, null: false
      t.string :content_version, null: false
      t.string :mode, null: false
      t.string :status, default: "ready", null: false
      t.json :questions, null: false
      t.json :answers, default: {}, null: false
      t.integer :question_index, default: 0, null: false
      t.text :current_draft, default: "", null: false
      t.integer :duration_seconds, null: false
      t.datetime :started_at
      t.datetime :deadline_at
      t.datetime :completed_at
      t.string :completion_reason
      t.json :review_entries, default: {}, null: false
      t.text :reflection, default: "", null: false
      t.integer :lock_version, default: 0, null: false
      t.timestamps
    end
    add_index :followup_rounds, [:interview_session_id, :client_request_id], unique: true, name: "followup_request_identity"
    add_index :followup_rounds, :interview_session_id, unique: true, name: "one_unfinished_followup", where: "status IN ('ready', 'active')"
  end
end
