# Spec 013: the user's projects (G1, G5), each with a kanban board of its epics. Users manage their own projects;
# the director may also add and change them from the chat (Q3).
class ProjectsController < ApplicationController
  rescue_from(ActiveRecord::RecordNotFound) { head :not_found }
  before_action :set_project, except: %i[index new create]

  def index
    @projects = current_user.projects.ordered
    @counts = current_user.work_items.group(:project_id, :state).count
  end

  def show
    items = @project.work_items.includes(tasks: :runs).order(:position, :id).to_a
    @columns = WorkItem::STATE_ORDER.index_with { |state| items.select { |i| i.state == state } }
    @cancelled = items.select { |i| i.state == "cancelled" }
  end

  def new
    @project = current_user.projects.new
  end

  def create
    @project = current_user.projects.new(project_params)
    if @project.save
      redirect_to @project, notice: "Project created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    if @project.update(project_params)
      redirect_to @project, notice: "Project saved."
    else
      render :edit, status: :unprocessable_content
    end
  end

  # R5: only an empty project can be deleted; others are archived.
  def destroy
    if @project.destroy
      redirect_to projects_path, notice: "Project deleted."
    else
      redirect_to @project, alert: "Only an empty project can be deleted. Archive it instead."
    end
  end

  def archive
    @project.update!(state: "archived")
    redirect_to @project, notice: "Archived: the director takes up no epics of this project until you make it active again."
  end

  def activate
    @project.update!(state: "active")
    redirect_to @project, notice: "Active again."
  end

  # Q10: the order of cards within one column, set by dragging on the board.
  def order
    ids = Array(params[:ids]).map(&:to_i)
    items = @project.work_items.where(id: ids).index_by(&:id)
    return head :unprocessable_content if ids.empty? || items.size != ids.size || items.values.map(&:state).uniq.size != 1

    WorkItem.transaction { ids.each_with_index { |id, i| items[id].update!(position: i + 1) if items[id].position != i + 1 } }
    head :no_content
  end

  private

  def set_project = @project = current_user.projects.find(params[:id])

  def project_params = params.expect(project: %i[name goal description])
end
