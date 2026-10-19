class AddPracticeAndReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :hint_reveals, id: :string do |t|
      t.references :interview_session, type: :string, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :content_version, null: false
      t.timestamps
    end
    add_index :hint_reveals, [:interview_session_id, :position], unique: true

    create_table :session_reviews, id: :string do |t|
      t.references :interview_session, type: :string, null: false, foreign_key: true, index: { unique: true }
      t.references :source_snapshot, type: :string, null: false, foreign_key: true
      t.string :content_version, null: false
      t.json :entries, default: {}, null: false
      t.text :reflection, default: "", null: false
      t.integer :lock_version, default: 0, null: false
      t.timestamps
    end
  end
end
