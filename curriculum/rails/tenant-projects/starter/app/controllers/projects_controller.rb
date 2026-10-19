# Existing implementation: reproduce the incident before repairing it.
class ProjectsController < ApplicationController
  def index
    render json: Project.where(organization_id: params[:organization_id]).order(:id)
  end
  def show
    render json: Project.find(params[:id])
  end
  def update
    project = Project.find(params[:id])
    project.update!(params.require(:project).permit(:name, :organization_id))
    render json: project
  end
end
