# Spec 011, G2/G8: an epic's page and history (owner fix after spec 013: no list page — epics live on their
# space boards). Try again, and Done and Cancel (spec 013, Q10).
class WorkItemsController < ApplicationController
  rescue_from(ActiveRecord::RecordNotFound) { head :not_found }

  def show
    @item = current_user.work_items.find(params[:id])
    @runs = @item.runs.recent.limit(20)
    @steps = @item.tasks.includes(:agent, :runs).order(:starts_at) # calendar steps from before spec 016 (Q7)
    @epic_steps = @item.epic_steps.includes(:agent, :runs, :step_reviews).to_a
    @decisions = @item.step_decisions.order(:id).to_a # spec 033
  end

  # A blocked item starts again from the director.
  def retry
    item = current_user.work_items.find(params[:id])
    return redirect_to(work_item_path(item), alert: "Only blocked items can be tried again.") unless item.state == "blocked"

    if item.step_decisions.pending.exists? # spec 033: a step waits for an answer, not for Try again
      return redirect_to(work_item_path(item, anchor: "decisions"), alert: "A step is waiting for your answer to its question.")
    end
    if item.active_steps.exists? # spec 016, G5: resume from the step that stopped
      StepChain.resume(item)
      return redirect_to(work_item_path(item), notice: "Resumed from the step that stopped.")
    end

    item.update!(state: "new", blocked_reason: nil)
    ManagementRunner.dispatch_due(user: current_user)
    redirect_to work_item_path(item), notice: item.reload.state == "blocked" ? item.blocked_reason : "Sent to the director again."
  end

  # Spec 033, G1: Approve a plan made at level Pytaj; it starts at its time.
  def approve
    item = current_user.work_items.find(params[:id])
    approved = item.approve_plan!
    redirect_to work_item_path(item), (approved ? { notice: "Plan approved." } : { alert: "This plan is not waiting for approval." })
  end

  # Spec 048: pause or resume one epic (the epic's page, and the work panel as JSON).
  def pause = toggle_pause(:pause!, "Paused: the current step finishes, then nothing more starts until you resume.")
  def resume = toggle_pause(:resume!, "Resumed.")

  # Spec 013, Q10: the user closes or cancels an epic by hand (on the board or the epic's page).
  def done
    item = current_user.work_items.find(params[:id])
    return redirect_back_or_to(work_item_path(item), alert: "This epic is already #{item.state_label}.") if %w[done cancelled].include?(item.state)

    item.done!
    StepChain.start_due(user: current_user) # spec 037, R6: the next epic of the space
    redirect_back_or_to work_item_path(item), notice: "Done: #{item.title}."
  end

  def cancel
    item = current_user.work_items.find(params[:id])
    return redirect_back_or_to(work_item_path(item), alert: "This epic is already #{item.state_label}.") if %w[done cancelled].include?(item.state)

    item.cancel!
    redirect_back_or_to work_item_path(item), notice: "Cancelled: #{item.title}. Its steps that had not started were removed."
  end

  private

  def toggle_pause(change, notice)
    item = current_user.work_items.find(params[:id])
    item.public_send(change)
    respond_to do |format|
      format.json { render json: { ok: true, paused: item.reload.paused? } }
      format.html { redirect_back_or_to work_item_path(item), notice: notice }
    end
  rescue WorkItem::NotPausable => e
    respond_to do |format|
      format.json { render json: { ok: false, error: e.message }, status: :unprocessable_content }
      format.html { redirect_back_or_to work_item_path(item), alert: e.message }
    end
  end
end
