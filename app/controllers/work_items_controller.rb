# Spec 011, G2/G8: the user's work list (kept by the director) and each item's history. Read-only, except Try again.
class WorkItemsController < ApplicationController
  rescue_from(ActiveRecord::RecordNotFound) { head :not_found }

  def index
    @items = current_user.work_items.listed
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
end
