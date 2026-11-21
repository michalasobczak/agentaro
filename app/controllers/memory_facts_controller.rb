# Spec 031, G7/R2/R3: the user's own facts — edit (a new version; the old one stays as history), pin, delete
# (permanently), keep or drop a proposed profile fact. Another user's fact is 404.
class MemoryFactsController < ApplicationController
  rescue_from(ActiveRecord::RecordNotFound) { head :not_found }
  before_action :set_fact

  def update
    edited = current_user.memory_facts.new(@fact.slice(:subject_type, :subject_id, :kind).merge(statement: params[:statement], status: "active",
                                           origin: "edited", confidence: 1.0, pinned: @fact.pinned))
    edited.kind = params[:kind] if MemoryFact::KINDS.include?(params[:kind])
    return redirect_to(brain_path, alert: edited.errors.full_messages.to_sentence) unless edited.valid?

    MemoryFact.transaction do
      edited.save!
      edited.supersede!(@fact)
      episode = MemoryEpisode.record!(current_user, "edit", "Edited on the Brain page: #{edited.statement}", source: edited)
      edited.memory_fact_sources.create!(memory_episode: episode)
    end
    redirect_to brain_path(anchor: "fact-#{edited.id}"), notice: "Saved; the earlier version is kept in its history."
  end

  def destroy
    @fact.destroy!
    redirect_to brain_path, notice: "Deleted for good."
  end

  def pin
    @fact.update!(pinned: !@fact.pinned)
    redirect_to brain_path(anchor: "fact-#{@fact.id}")
  end

  def approve
    Brain.approve!(@fact) if @fact.status == "proposed"
    redirect_to brain_path, notice: "Kept."
  end

  def reject
    @fact.invalidate! if @fact.status == "proposed"
    redirect_to brain_path, notice: "Dropped."
  end

  private

  def set_fact = @fact = current_user.memory_facts.find(params[:id])
end
