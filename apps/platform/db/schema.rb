# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_18_000006) do
  create_table "accounts", id: :string, force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_accounts_on_email", unique: true
  end

  create_table "automated_reviews", id: :string, force: :cascade do |t|
    t.string "interview_session_id", null: false
    t.string "source_snapshot_id", null: false
    t.string "client_request_id", null: false
    t.string "status", default: "queued", null: false
    t.string "prompt_version", null: false
    t.string "content_version", null: false
    t.json "input", null: false
    t.json "report"
    t.string "worker_id"
    t.string "lease_digest"
    t.datetime "lease_expires_at"
    t.string "model"
    t.string "model_digest"
    t.string "error_code"
    t.json "usage"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["interview_session_id", "client_request_id"], name: "review_request_identity", unique: true
    t.index ["interview_session_id"], name: "index_automated_reviews_on_interview_session_id"
    t.index ["interview_session_id"], name: "one_pending_review_per_session", unique: true, where: "status IN ('queued', 'running')"
    t.index ["source_snapshot_id"], name: "index_automated_reviews_on_source_snapshot_id"
    t.index ["status", "created_at"], name: "index_automated_reviews_on_status_and_created_at"
    t.index ["worker_id"], name: "one_review_per_worker", unique: true, where: "status = 'running'"
  end

  create_table "execution_requests", id: :string, force: :cascade do |t|
    t.string "interview_session_id", null: false
    t.string "source_snapshot_id", null: false
    t.string "client_request_id", null: false
    t.string "purpose", null: false
    t.string "status", default: "queued", null: false
    t.string "worker_id"
    t.string "lease_digest"
    t.datetime "lease_expires_at"
    t.json "result"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["interview_session_id", "client_request_id"], name: "execution_idempotency", unique: true
    t.index ["interview_session_id"], name: "index_execution_requests_on_interview_session_id"
    t.index ["source_snapshot_id"], name: "index_execution_requests_on_source_snapshot_id"
    t.index ["status", "created_at"], name: "index_execution_requests_on_status_and_created_at"
    t.index ["worker_id"], name: "one_job_per_worker", unique: true, where: "status = 'leased'"
  end

  create_table "exercise_versions", id: :string, force: :cascade do |t|
    t.string "slug", null: false
    t.integer "version", null: false
    t.string "title", null: false
    t.string "track", null: false
    t.string "operation"
    t.text "brief", null: false
    t.json "starter_files", default: {}, null: false
    t.integer "duration_minutes", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug", "version"], name: "index_exercise_versions_on_slug_and_version", unique: true
  end

  create_table "followup_rounds", id: :string, force: :cascade do |t|
    t.string "interview_session_id", null: false
    t.string "source_snapshot_id", null: false
    t.string "client_request_id", null: false
    t.string "content_version", null: false
    t.string "mode", null: false
    t.string "status", default: "ready", null: false
    t.json "questions", null: false
    t.json "answers", default: {}, null: false
    t.integer "question_index", default: 0, null: false
    t.text "current_draft", default: "", null: false
    t.integer "duration_seconds", null: false
    t.datetime "started_at"
    t.datetime "deadline_at"
    t.datetime "completed_at"
    t.string "completion_reason"
    t.json "review_entries", default: {}, null: false
    t.text "reflection", default: "", null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["interview_session_id", "client_request_id"], name: "followup_request_identity", unique: true
    t.index ["interview_session_id"], name: "index_followup_rounds_on_interview_session_id"
    t.index ["interview_session_id"], name: "one_unfinished_followup", unique: true, where: "status IN ('ready', 'active')"
    t.index ["source_snapshot_id"], name: "index_followup_rounds_on_source_snapshot_id"
  end

  create_table "hint_reveals", id: :string, force: :cascade do |t|
    t.string "interview_session_id", null: false
    t.integer "position", null: false
    t.string "content_version", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["interview_session_id", "position"], name: "index_hint_reveals_on_interview_session_id_and_position", unique: true
    t.index ["interview_session_id"], name: "index_hint_reveals_on_interview_session_id"
  end

  create_table "interview_sessions", id: :string, force: :cascade do |t|
    t.string "account_id", null: false
    t.string "exercise_version_id", null: false
    t.string "mode", null: false
    t.string "status", default: "draft", null: false
    t.string "current_revision"
    t.string "submitted_revision"
    t.datetime "started_at"
    t.datetime "deadline_at"
    t.datetime "submitted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "practice_focus"
    t.string "revision_of_id"
    t.string "rework_request_id"
    t.json "revision_context"
    t.datetime "archived_at"
    t.index ["account_id", "archived_at", "updated_at"], name: "idx_on_account_id_archived_at_updated_at_d6fbbe1791"
    t.index ["account_id"], name: "index_interview_sessions_on_account_id"
    t.index ["exercise_version_id"], name: "index_interview_sessions_on_exercise_version_id"
    t.index ["revision_of_id", "rework_request_id"], name: "rework_request_identity", unique: true
    t.index ["revision_of_id"], name: "index_interview_sessions_on_revision_of_id"
    t.index ["revision_of_id"], name: "one_unfinished_rework", unique: true, where: "revision_of_id IS NOT NULL AND status IN ('draft', 'preparing', 'ready', 'active')"
  end

  create_table "mock_interview_stages", id: :string, force: :cascade do |t|
    t.string "mock_interview_id", null: false
    t.string "exercise_version_id"
    t.string "interview_session_id"
    t.string "followup_round_id"
    t.integer "position", null: false
    t.string "kind", null: false
    t.string "title", null: false
    t.integer "duration_seconds", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["exercise_version_id"], name: "index_mock_interview_stages_on_exercise_version_id"
    t.index ["followup_round_id"], name: "index_mock_interview_stages_on_followup_round_id", unique: true
    t.index ["interview_session_id"], name: "index_mock_interview_stages_on_interview_session_id", unique: true
    t.index ["mock_interview_id", "position"], name: "index_mock_interview_stages_on_mock_interview_id_and_position", unique: true
    t.index ["mock_interview_id"], name: "index_mock_interview_stages_on_mock_interview_id"
  end

  create_table "mock_interviews", id: :string, force: :cascade do |t|
    t.string "account_id", null: false
    t.string "client_request_id", null: false
    t.string "plan_key", null: false
    t.string "title", null: false
    t.string "status", default: "ready", null: false
    t.integer "stage_index", default: 0, null: false
    t.datetime "started_at"
    t.datetime "deadline_at"
    t.datetime "completed_at"
    t.string "completion_reason"
    t.text "reflection", default: "", null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "archived_at"
    t.index ["account_id", "archived_at", "created_at"], name: "idx_on_account_id_archived_at_created_at_c2e487f989"
    t.index ["account_id", "client_request_id"], name: "index_mock_interviews_on_account_id_and_client_request_id", unique: true
    t.index ["account_id"], name: "index_mock_interviews_on_account_id"
  end

  create_table "review_workers", id: :string, force: :cascade do |t|
    t.string "model", null: false
    t.string "model_digest", null: false
    t.datetime "last_seen_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "session_reviews", id: :string, force: :cascade do |t|
    t.string "interview_session_id", null: false
    t.string "source_snapshot_id", null: false
    t.string "content_version", null: false
    t.json "entries", default: {}, null: false
    t.text "reflection", default: "", null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["interview_session_id"], name: "index_session_reviews_on_interview_session_id", unique: true
    t.index ["source_snapshot_id"], name: "index_session_reviews_on_source_snapshot_id"
  end

  create_table "source_snapshots", id: :string, force: :cascade do |t|
    t.string "interview_session_id", null: false
    t.string "revision", null: false
    t.json "files", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["interview_session_id", "revision"], name: "snapshot_revision_identity", unique: true
    t.index ["interview_session_id"], name: "index_source_snapshots_on_interview_session_id"
  end

  create_table "worker_nodes", id: :string, force: :cascade do |t|
    t.json "capabilities", default: [], null: false
    t.datetime "last_seen_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "automated_reviews", "interview_sessions"
  add_foreign_key "automated_reviews", "source_snapshots"
  add_foreign_key "execution_requests", "interview_sessions"
  add_foreign_key "execution_requests", "source_snapshots"
  add_foreign_key "followup_rounds", "interview_sessions"
  add_foreign_key "followup_rounds", "source_snapshots"
  add_foreign_key "hint_reveals", "interview_sessions"
  add_foreign_key "interview_sessions", "accounts"
  add_foreign_key "interview_sessions", "exercise_versions"
  add_foreign_key "interview_sessions", "interview_sessions", column: "revision_of_id"
  add_foreign_key "mock_interview_stages", "exercise_versions"
  add_foreign_key "mock_interview_stages", "followup_rounds"
  add_foreign_key "mock_interview_stages", "interview_sessions"
  add_foreign_key "mock_interview_stages", "mock_interviews"
  add_foreign_key "mock_interviews", "accounts"
  add_foreign_key "session_reviews", "interview_sessions"
  add_foreign_key "session_reviews", "source_snapshots"
  add_foreign_key "source_snapshots", "interview_sessions"
end
