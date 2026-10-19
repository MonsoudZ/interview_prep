class ExerciseVersion < ApplicationRecord
  validates :track, inclusion: { in: %w[rails ruby system_design] }
  validates :slug, :title, :brief, presence: true
  validates :version, :duration_minutes, numericality: { only_integer: true, greater_than: 0 }
  validates :version, uniqueness: { scope: :slug }
  def readonly?
    persisted?
  end
end
