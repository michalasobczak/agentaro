# Spec 011, G2/G8: the user's work list (kept by the director) and each item's history. Read-only, except Try again.
class WorkItemsController < ApplicationController
  rescue_from(ActiveRecord::RecordNotFound) { head :not_found }

  def index
    @projects = current_user.projects.ordered
    @project = @projects.find { |p| p.id == params[:project].to_i } # spec 013: filter by project
    @items = current_user.work_items.includes(:project).listed
    @items = @items.where(project: @project) if @project
  end

  def show
    @item = current_user.work_items.find(params[:id])
    @runs = @item.runs.recent.limit(20)
    @steps = @item.tasks.includes(:agent, :runs).order(:starts_at)
  end

  # A blocked item starts again from the director.
  def retry
    item = current_user.work_items.find(params[:id])
    return redirect_to(work_item_path(item), alert: "Only blocked items can be tried again.") unless item.state == "blocked"

    item.update!(state: "new", blocked_reason: nil)
    ManagementRunner.dispatch_due(user: current_user)
    redirect_to work_item_path(item), notice: item.reload.state == "blocked" ? item.blocked_reason : "Sent to the director again."
  end

  # Spec 013, Q10: the user closes or cancels an epic by hand (on the board or the epic's page).
  def done
    item = current_user.work_items.find(params[:id])
    return redirect_back_or_to(work_item_path(item), alert: "This epic is already #{item.state_label}.") if %w[done cancelled].include?(item.state)

    item.done!
    redirect_back_or_to work_item_path(item), notice: "Done: #{item.title}."
  end

  def cancel
    item = current_user.work_items.find(params[:id])
    return redirect_back_or_to(work_item_path(item), alert: "This epic is already #{item.state_label}.") if %w[done cancelled].include?(item.state)

    item.cancel!
    redirect_back_or_to work_item_path(item), notice: "Cancelled: #{item.title}. Its steps that had not started were removed."
  end
end
