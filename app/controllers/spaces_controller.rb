# Spec 013: the user's spaces (G1, G5), each with a kanban board of its epics. Users manage their own spaces;
# the director may also add and change them from the chat (Q3).
class SpacesController < ApplicationController
  rescue_from(ActiveRecord::RecordNotFound) { head :not_found }
  before_action :set_space, except: %i[index new create folders]
  rate_limit to: 300, within: 1.minute, only: :folders, by: -> { current_user.id }, store: RATE_LIMIT_STORE,
             with: -> { render json: { exists: false, folders: [] }, status: :too_many_requests }

  # Owner fix after spec 018: folders under the typed path, for the working-folder field.
  def folders
    result = FolderSuggestions.for(params[:path], current_user)
    render json: { exists: result.exists, folders: result.folders }
  end

  def index
    @spaces = current_user.spaces.ordered
    @counts = current_user.work_items.group(:space_id, :state).count
  end

  def show
    items = @space.work_items.includes(tasks: :runs).order(:position, :id).to_a
    @columns = WorkItem::STATE_ORDER.index_with { |state| items.select { |i| i.state == state } }
    @cancelled = items.select { |i| i.state == "cancelled" }
  end

  def new
    @space = current_user.spaces.new(kind: params[:kind] == "team" ? "team" : "project")
  end

  def create
    @space = current_user.spaces.new(space_params)
    if @space.save
      redirect_to @space, notice: "Space created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    if @space.update(space_params)
      redirect_to @space, notice: "Space saved."
    else
      render :edit, status: :unprocessable_content
    end
  end

  # R5: only an empty space can be deleted; others are archived.
  def destroy
    if @space.destroy
      redirect_to spaces_path, notice: "Space deleted."
    else
      redirect_to @space, alert: "Only an empty space can be deleted. Archive it instead."
    end
  end

  def archive
    @space.update!(state: "archived")
    redirect_to @space, notice: "Archived: the director takes up no epics of this space until you make it active again."
  end

  def activate
    @space.update!(state: "active")
    redirect_to @space, notice: "Active again."
  end

  # Q10: the order of cards within one column, set by dragging on the board.
  def order
    ids = Array(params[:ids]).map(&:to_i)
    items = @space.work_items.where(id: ids).index_by(&:id)
    return head :unprocessable_content if ids.empty? || items.size != ids.size || items.values.map(&:state).uniq.size != 1

    WorkItem.transaction { ids.each_with_index { |id, i| items[id].update!(position: i + 1) if items[id].position != i + 1 } }
    head :no_content
  end

  private

  def set_space = @space = current_user.spaces.find(params[:id])

  def space_params = params.expect(space: %i[kind name goal description working_dir])
end
