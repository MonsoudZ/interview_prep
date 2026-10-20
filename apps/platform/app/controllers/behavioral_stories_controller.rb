class BehavioralStoriesController < ApplicationController
  rescue_from SessionCommandError do |error|
    render json: { error: error.message }, status: error.status
  end
  def index
    scope = BehavioralStory.where(account: current_account)
    scope = params[:archived] == "true" ? scope.where.not(archived_at: nil) : scope.where(archived_at: nil)
    exercises = ExerciseVersion.where(track: "behavioral").group_by(&:slug).values.map { |versions| versions.max_by(&:version) }
    render json: { topics: BehavioralContent::TOPICS, sections: BehavioralContent::LABELS, stories: scope.order(updated_at: :desc, id: :desc).map { |story| BehavioralStories.present(story) },
      exercises: exercises.map { |exercise| { id: exercise.id, title: exercise.title, topic: BehavioralContent.find(exercise).fetch("topic") } } }
  end
  def show
    render json: BehavioralStories.present(owned)
  end
  def create
    render json: BehavioralStories.present(BehavioralStories.create!(current_account, params[:client_request_id], params.require(:story))), status: :created
  end
  def update
    render json: BehavioralStories.present(BehavioralStories.update!(owned, params))
  end
  def rehearse
    record = BehavioralStories.rehearse!(current_account, owned, params[:exercise_id], params[:client_request_id], params[:expected_version])
    render json: SessionPresenter.call(record), status: :created
  end
  private
  def owned
    @owned ||= BehavioralStory.where(account: current_account).find(params[:id])
  end
end
