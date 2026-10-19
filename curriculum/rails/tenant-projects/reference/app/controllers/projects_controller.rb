class ProjectsController < ApplicationController
  before_action :authenticate
  def index
    render json: scope.order(:id).map { |p| serialize(p) }
  end
  def show
    project = find_project
    render json: serialize(project) if project
  end
  def update
    project = find_project
    return unless project
    return failure(:forbidden, "Editor role required") unless @user.role == "editor"
    input = params[:project]
    name = input[:name] if input.is_a?(ActionController::Parameters)
    unless name.is_a?(String) && !name.strip.empty? && name.length <= 80
      return failure(:unprocessable_content, "A valid name is required")
    end
    project.update!(name: name)
    render json: serialize(project)
  end
  private
  def authenticate
    match = /\ABearer ([^\s]+)\z/.match(request.headers["Authorization"].to_s)
    @user = User.find_by(api_token: match[1]) if match
    failure(:unauthorized, "Authentication required") unless @user
  end
  def scope
    Project.where(organization_id: @user.organization_id)
  end
  def find_project
    id = params[:id].to_s
    project = scope.find_by(id: id) if id.match?(/\A[1-9][0-9]*\z/)
    failure(:not_found, "Project not found") unless project
    project
  end
  def serialize(project)
    project.as_json(only: [:id, :name, :organization_id])
  end
  def failure(status, message)
    render json: { errors: { base: [message] } }, status: status
  end
end
