class AddAutomatedReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :review_workers, id: :string do |t|
      t.string :model, null: false
      t.string :model_digest, null: false
      t.datetime :last_seen_at, null: false
      t.timestamps
    end
    create_table :automated_reviews, id: :string do |t|
      t.references :interview_session, type: :string, null: false, foreign_key: true
      t.references :source_snapshot, type: :string, null: false, foreign_key: true
      t.string :client_request_id, null: false
      t.string :status, default: "queued", null: false
      t.string :prompt_version, null: false
      t.string :content_version, null: false
      t.json :input, null: false
      t.json :report
      t.string :worker_id
      t.string :lease_digest
      t.datetime :lease_expires_at
      t.string :model
      t.string :model_digest
      t.string :error_code
      t.json :usage
      t.timestamps
    end
    add_index :automated_reviews, [:interview_session_id, :client_request_id], unique: true, name: "review_request_identity"
    add_index :automated_reviews, :interview_session_id, unique: true, where: "status IN ('queued', 'running')", name: "one_pending_review_per_session"
    add_index :automated_reviews, :worker_id, unique: true, where: "status = 'running'", name: "one_review_per_worker"
    add_index :automated_reviews, [:status, :created_at]
  end
end
