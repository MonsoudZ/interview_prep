class AddSessionArchives < ActiveRecord::Migration[8.1]
  def change
    add_column :interview_sessions, :archived_at, :datetime
    add_column :mock_interviews, :archived_at, :datetime
    add_index :interview_sessions, [:account_id, :archived_at, :updated_at]
    add_index :mock_interviews, [:account_id, :archived_at, :created_at]
  end
end
