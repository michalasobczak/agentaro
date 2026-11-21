# Spec 033: the owner answers a step's question (G3) or corrects an assumption (G5), on their own epics only (R5).
class StepDecisionsController < ApplicationController
  rescue_from(ActiveRecord::RecordNotFound) { head :not_found }

  def answer
    decision = find_decision
    value = params[:answer].is_a?(String) ? params[:answer] : ""
    answered = decision.answer_by_owner!(value)
    redirect_to work_item_path(decision.work_item), (answered ? { notice: "Answered; the step goes on." } : { alert: "This question was already answered." })
  rescue ArgumentError => e
    redirect_to work_item_path(decision.work_item, anchor: "decisions"), alert: e.message.upcase_first
  end

  def correct
    decision = find_decision
    decision.correct!(params[:correction].is_a?(String) ? params[:correction] : "")
    redirect_to work_item_path(decision.work_item, anchor: "decisions"), notice: "Corrected. Agentaro remembers it for this space; press Try again or start the epic anew to redo the work."
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to work_item_path(decision.work_item, anchor: "decisions"), alert: e.message.upcase_first
  end

  private

  def find_decision = StepDecision.joins(:work_item).where(work_items: { user_id: current_user.id }).find(params[:id])
end
