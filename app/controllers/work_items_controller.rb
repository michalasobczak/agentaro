# Spec 011, G2/G8: an epic's page and history (owner fix after spec 013: no list page — epics live on their
# space boards). Try again, and Done and Cancel (spec 013, Q10).
class WorkItemsController < ApplicationController
  rescue_from(ActiveRecord::RecordNotFound) { head :not_found }

  def show
    @item = current_user.work_items.find(params[:id])
    @runs = @item.runs.recent.limit(20)
    @steps = @item.tasks.includes(:agent, :runs).order(:starts_at) # calendar steps from before spec 016 (Q7)
    @epic_steps = @item.epic_steps.includes(:agent, :runs).to_a
  end

  # A blocked item starts again from the director.
  def retry
    item = current_user.work_items.find(params[:id])
    return redirect_to(work_item_path(item), alert: "Only blocked items can be tried again.") unless item.state == "blocked"

    if item.active_steps.exists? # spec 016, G5: resume from the step that stopped
      StepChain.resume(item)
      return redirect_to(work_item_path(item), notice: "Resumed from the step that stopped.")
    end

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
