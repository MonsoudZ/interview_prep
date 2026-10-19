class AddReworkSessions < ActiveRecord::Migration[8.1]
  def change
    add_reference :interview_sessions, :revision_of, type: :string, foreign_key: { to_table: :interview_sessions }
    add_column :interview_sessions, :rework_request_id, :string
    add_column :interview_sessions, :revision_context, :json
    add_index :interview_sessions, [:revision_of_id, :rework_request_id], unique: true, name: "rework_request_identity"
    add_index :interview_sessions, :revision_of_id, unique: true, name: "one_unfinished_rework",
      where: "revision_of_id IS NOT NULL AND status IN ('draft', 'preparing', 'ready', 'active')"
  end
end
