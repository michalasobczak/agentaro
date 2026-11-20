# Spec 023: whether each agent is busy or free for one user, and on what. Derived from runs; nothing is stored (G1).
# An agent is busy while one of the user's own `epic_step` runs is `running` with it, and the run's step is `running`
# in its epic's active plan (R1). Queued runs (R2), finished or interrupted runs (R3), other users' runs (R8) and
# runs of deleted agents (R6) never count. A step that keeps running after its epic was cancelled or closed by hand
# stays busy, marked `cancelled` (R4, Q2).
module AgentStatus
  TITLE_LIMIT = 80 # R7: in labels; the full title goes into `title=`

  Activity = Data.define(:agent_id, :run_id, :epic_id, :epic, :epic_state, :step_id, :step, :of, :title, :started_at) do
    def cancelled = epic_state != "planned"

    # R7, R4: "World review · step 2/4: Collect evidence"; a stopped epic says so.
    def label(limit: TITLE_LIMIT)
      where = cancelled ? "finishing a step of a #{epic_state == "cancelled" ? "cancelled" : "closed"} epic: #{epic}" : epic
      "#{where} · step #{step}/#{of}: #{title.to_s.truncate(limit)}"
    end

    def as_json(*)
      { epic_id: epic_id, epic: epic, step: step, of: of, title: title, cancelled: cancelled, epic_state: epic_state, started_at: started_at&.iso8601 }
    end
  end

  module_function

  # { agent_id => [Activity, …] } for busy agents only, oldest start first (R5). One query for the runs.
  def for(user)
    runs = TaskRun.where(user_id: user.id, purpose: "epic_step", state: "running").where.not(agent_id: nil)
                  .includes(epic_step: :work_item).order(:started_at, :id).to_a
    counts = {}
    runs.filter_map do |run|
      step = run.epic_step
      item = step&.work_item
      next unless item && item.user_id == user.id && step.state == "running" && step.position >= item.active_step_from.to_i

      of = counts[item.id] ||= item.active_steps.count
      Activity.new(agent_id: run.agent_id, run_id: run.id, epic_id: item.id, epic: item.title, epic_state: item.state,
                   step_id: step.id, step: step.position - item.active_step_from.to_i + 1, of: of, title: step.title,
                   started_at: run.started_at)
    end.group_by(&:agent_id)
  end

  # A fingerprint of the busy rows: it changes when a step starts or ends, or its epic is stopped (spec §5, events).
  def stamp(user, statuses = self.for(user))
    rows = statuses.values.flatten.map { |a| [ a.run_id, a.step_id, a.epic_state, a.agent_id, a.step, a.of ] }.sort
    ChangeStamp.digest(rows.size, rows.inspect)
  end

  # "busy · World review · step 2/4: Collect evidence" or "free" (G2).
  def label(activities)
    return "free" if activities.blank?

    "busy · #{activities.first.label}#{" · +#{activities.size - 1} more" if activities.size > 1}"
  end

  # "3 min", "1 h 5 min" — how long the activity has run (stuck runs become visible, spec §5 Resilience).
  def elapsed(started_at, now = Time.current)
    return nil unless started_at

    minutes = [ ((now - started_at) / 60).floor, 0 ].max
    minutes < 60 ? "#{minutes} min" : "#{minutes / 60} h #{minutes % 60} min"
  end

  # The agents of the user's team whose status is shown: members, then the director and verifier (G3).
  # Returns [[agent, role_label, member?], …], each agent once.
  def team(user)
    roles = user.team_roles.includes(agent: :executor).order(:id).to_a
    members = roles.select { |r| r.role == "member" }
    list = members.map { |r| [ r.agent, r.role_text.presence || "Member", true ] }
    roles.each do |r|
      next unless %w[director verifier].include?(r.role)
      next if list.any? { |agent, _, _| agent.id == r.agent_id }

      list << [ r.agent, r.role.capitalize, false ]
    end
    list
  end

  # Spec 023 contract: { stamp, agents: [{ id, name, role, member, status, label, show_dot, activities: […] }] }.
  # `show_dot`: members always; the director and verifier only when busy (R11).
  def json(user, statuses = self.for(user))
    agents = team(user).map do |agent, role, member|
      activities = statuses[agent.id] || []
      { id: agent.id, name: agent.name, role: role, member: member, status: activities.any? ? "busy" : "free", label: label(activities),
        show_dot: member || activities.any?, activities: activities.map(&:as_json) }
    end
    { stamp: stamp(user, statuses), agents: agents }
  end
end
