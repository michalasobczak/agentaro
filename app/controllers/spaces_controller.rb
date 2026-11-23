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
    @layout = SpaceGroup.layout(current_user, @spaces.to_a) # spec 051
    @counts = current_user.work_items.select(:space_id, :state, :started_at).each_with_object(Hash.new(0)) { |i, h| h[[ i.space_id, i.board_state ]] += 1 }
  end

  def show
    items = @space.work_items.includes(tasks: :runs).order(:position, :id).to_a
    @columns = WorkItem::BOARD_STATES.index_with { |state| items.select { |i| i.board_state == state } }
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

  # R5: an empty space can be deleted; others are archived first. Spec 025: an archived space is deleted with its
  # epics, steps, calendar entries and runs; steps still running in it are stopped.
  def destroy
    if !@space.active?
      name = @space.name
      @space.purge!
      redirect_to spaces_path, notice: "Space #{name} deleted with its epics."
    elsif @space.destroy
      redirect_to spaces_path, notice: "Space deleted."
    else
      redirect_to @space, alert: "Only an empty space can be deleted. Archive it first."
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
    return head :unprocessable_content if ids.empty? || items.size != ids.size || items.values.map(&:board_state).uniq.size != 1

    WorkItem.transaction { ids.each_with_index { |id, i| items[id].update!(position: i + 1) if items[id].position != i + 1 } }
    head :no_content
  end

  # Spec 052, G2 (a): a CI run on the button.
  def build
    run = Ci.queue!(@space, trigger: "manual", user: current_user)
    notice = run ? "CI queued: it starts when no step works in the folder." : (@space.ci_state == "error" ? @space.ci_log : "CI is already waiting, or the space has no build or test.")
    redirect_to space_path(@space, anchor: "ci"), notice: notice
  end

  # Spec 052, G4: start, stop or restart the space's server.
  def server
    case params[:do]
    when "start", "restart" then Ci::Server.start!(@space)
    when "stop" then Ci::Server.stop!(@space)
    else return head :unprocessable_content
    end
    redirect_to space_path(@space, anchor: "ci"), notice: "Server: #{@space.reload.server_state}#{" — #{@space.server_note}" if @space.server_note}."
  end

  # Spec 051, G3: a space dragged into a group (or out of every group: no group_id) at a 1-based place.
  def place
    group = params[:group_id].present? ? current_user.space_groups.find(params[:group_id]) : nil
    @space.place!(group, params[:index].to_i.clamp(1, 1000))
    render json: { ok: true, group_id: group&.id, position: @space.position }
  end

  private

  def set_space = @space = current_user.spaces.find(params[:id])

  def space_params
    attrs = params.expect(space: %i[kind name goal description working_dir autonomy_level work_tempo])
    attrs[:autonomy_level] = attrs[:autonomy_level].presence&.to_i if attrs.key?(:autonomy_level) # spec 033: "" = the owner's default
    attrs[:work_tempo] = attrs[:work_tempo].presence&.to_i if attrs.key?(:work_tempo) # spec 041, G5: "" = the owner's default
    attrs
  end
end
