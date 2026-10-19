class CreatePlatform < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts, id: :string do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :password_digest, null: false
      t.timestamps
    end
    add_index :accounts, :email, unique: true
    create_table :exercise_versions, id: :string do |t|
      t.string :slug, null: false
      t.integer :version, null: false
      t.string :title, null: false
      t.string :track, null: false
      t.string :operation
      t.text :brief, null: false
      t.json :starter_files, default: {}, null: false
      t.integer :duration_minutes, null: false
      t.timestamps
    end
    add_index :exercise_versions, [:slug, :version], unique: true
    create_table :interview_sessions, id: :string do |t|
      t.references :account, type: :string, null: false, foreign_key: true
      t.references :exercise_version, type: :string, null: false, foreign_key: true
      t.string :mode, null: false
      t.string :status, default: "draft", null: false
      t.string :current_revision
      t.string :submitted_revision
      t.datetime :started_at
      t.datetime :deadline_at
      t.datetime :submitted_at
      t.timestamps
    end
    create_table :source_snapshots, id: :string do |t|
      t.references :interview_session, type: :string, null: false, foreign_key: true
      t.string :revision, null: false
      t.json :files, null: false
      t.timestamps
    end
    add_index :source_snapshots, [:interview_session_id, :revision], unique: true, name: "snapshot_revision_identity"
    create_table :worker_nodes, id: :string do |t|
      t.json :capabilities, default: [], null: false
      t.datetime :last_seen_at, null: false
      t.timestamps
    end
    create_table :execution_requests, id: :string do |t|
      t.references :interview_session, type: :string, null: false, foreign_key: true
      t.references :source_snapshot, type: :string, null: false, foreign_key: true
      t.string :client_request_id, null: false
      t.string :purpose, null: false
      t.string :status, default: "queued", null: false
      t.string :worker_id
      t.string :lease_digest
      t.datetime :lease_expires_at
      t.json :result
      t.timestamps
    end
    add_index :execution_requests, [:interview_session_id, :client_request_id], unique: true, name: "execution_idempotency"
    add_index :execution_requests, [:status, :created_at]
    add_index :execution_requests, :worker_id, unique: true, where: "status = 'leased'", name: "one_job_per_worker"
  end
end
