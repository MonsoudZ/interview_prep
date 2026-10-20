class AddBehavioralStories < ActiveRecord::Migration[8.1]
  def change
    create_table :behavioral_stories, id: :string do |t|
      t.references :account, type: :string, null: false, foreign_key: true
      t.string :client_request_id, null: false
      t.string :title, null: false
      t.json :topics, null: false, default: []
      t.json :sections, null: false, default: {}
      t.string :readiness, null: false, default: "draft"
      t.datetime :archived_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :behavioral_stories, [:account_id, :client_request_id], unique: true
    add_column :interview_sessions, :behavioral_context, :json
    add_column :interview_sessions, :behavioral_request_id, :string
    add_index :interview_sessions, [:account_id, :behavioral_request_id], unique: true
  end
end
