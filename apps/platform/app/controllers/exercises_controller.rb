class ExercisesController < ApplicationController
  def index
    render json: { exercises: ExerciseVersion.all.group_by(&:slug).values.map { |versions| versions.max_by(&:version) }.sort_by { |exercise| [exercise.track, RailsCurriculum::ORDER.index(exercise.slug) || 99, exercise.title, -exercise.version] }.map { |exercise|
      ExerciseCatalog.details(exercise).merge(exercise.as_json(only: [:id, :slug, :version, :title, :track, :duration_minutes])).merge(
        executable: exercise.operation.present?, worker_available: exercise.operation.present? && WorkerNode.available?(exercise.operation))
    } }
  end
end
