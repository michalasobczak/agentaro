# Spec 031, G7: the Brain page — the user's core blocks and facts, with their sources and history; edit, pin, delete,
# keep or drop proposed profile facts (R2). (Q5's history import was withdrawn by the owner; see the spec.)
class BrainsController < ApplicationController
  def show
    @status = Brain.client.status
    facts = current_user.memory_facts.includes(:supersedes, memory_fact_sources: :memory_episode).order(pinned: :desc, confidence: :desc, id: :desc).to_a
    @proposed = facts.select { |f| f.status == "proposed" }
    @active = facts.select { |f| f.status == "active" }.group_by(&:subject_key)
    @old = facts.select { |f| f.status.in?(%w[invalid archived]) }.sort_by { |f| -(f.invalid_at || f.updated_at).to_i }.first(100)
    @spaces = current_user.spaces.active.ordered.to_a
    @agents = Agent.where(id: Brain.agent_ids(current_user)).order(:name).to_a
    @blocks = current_user.memory_blocks.index_by { |b| [ b.scope_type, b.scope_id ] }
    @waiting = current_user.memory_episodes.pending.count
  end

  # G1: a core block, saved as typed (the version counts up).
  def block
    block = MemoryBlock.for(current_user, params[:scope_type].to_s, params[:scope_id].presence&.to_i)
    block.content = params[:content]
    if block.save
      redirect_to brain_path(anchor: "blocks"), notice: "Saved."
    else
      redirect_to brain_path(anchor: "blocks"), alert: block.errors.full_messages.to_sentence
    end
  end
end
