class EventsController < ApplicationController
  rescue_from ActionDispatch::Http::Parameters::ParseError do
    render json: { errors: { base: ["Malformed JSON"] } }, status: :bad_request
  end

  def index
    scope = Event.order(:id)
    if params.key?(:repository_id)
      unless positive_id?(params[:repository_id])
        return render json: { errors: { repository_id: ["must be a positive integer"] } }, status: :bad_request
      end
      scope = scope.where(repository_id: params[:repository_id].to_i)
    end
    render json: scope
  end

  def show
    event = Event.find_by(id: params[:id].to_i) if positive_id?(params[:id])
    if event
      render json: event
    else
      render json: { errors: { base: ["Event not found"] } }, status: :not_found
    end
  end

  def create
    body = params[:event]
    unless body.is_a?(ActionController::Parameters)
      return render json: { errors: { base: ["event must be an object"] } }, status: :unprocessable_content
    end
    event = Event.new(body.permit(:event_type, :actor_id, :repository_id, :occurred_at))
    if event.save
      render json: event, status: :created
    else
      render json: { errors: event.errors.to_hash }, status: :unprocessable_content
    end
  end

  private

  def positive_id?(value)
    value.is_a?(String) && value.match?(/\A[0-9]+\z/) && value.to_i.positive?
  end
end
