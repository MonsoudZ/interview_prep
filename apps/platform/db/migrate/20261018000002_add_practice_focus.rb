class AddPracticeFocus < ActiveRecord::Migration[8.1]
  def change
    add_column :interview_sessions, :practice_focus, :json
  end
end
