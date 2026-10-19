class AddMockInterviews < ActiveRecord::Migration[8.1]
  def change
    create_table :mock_interviews, id: :string do |t|
      t.references :account, type: :string, null: false, foreign_key: true
      t.string :client_request_id, null: false
      t.string :plan_key, null: false
      t.string :title, null: false
      t.string :status, null: false, default: "ready"
      t.integer :stage_index, null: false, default: 0
      t.datetime :started_at
      t.datetime :deadline_at
      t.datetime :completed_at
      t.string :completion_reason
      t.text :reflection, null: false, default: ""
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :mock_interviews, [:account_id, :client_request_id], unique: true
    create_table :mock_interview_stages, id: :string do |t|
      t.references :mock_interview, type: :string, null: false, foreign_key: true
      t.references :exercise_version, type: :string, foreign_key: true
      t.references :interview_session, type: :string, foreign_key: true, index: { unique: true }
      t.references :followup_round, type: :string, foreign_key: true, index: { unique: true }
      t.integer :position, null: false
      t.string :kind, null: false
      t.string :title, null: false
      t.integer :duration_seconds, null: false
      t.timestamps
    end
    add_index :mock_interview_stages, [:mock_interview_id, :position], unique: true
  end
end
