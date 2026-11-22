# Spec 023: whether each agent is busy or free for one user, and on what. Derived from runs; nothing is stored (G1).
# Spec 036, S3: the status is the agent's load against its limit ("2/6 in progress"); busy only at the limit.
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
  # Spec 036: the load of the team's agents (counts and limits) changes it too.
  def stamp(user, statuses = self.for(user), counts = nil)
    rows = statuses.values.flatten.map { |a| [ a.run_id, a.step_id, a.epic_state, a.agent_id, a.step, a.of ] }.sort
    ids = team(user).map { |agent, _, _| agent.id }
    counts ||= running_counts(ids)
    load = Agent.where(id: ids).order(:id).pluck(:id, :max_parallel_tasks).map { |id, limit| [ id, counts[id].to_i, limit ] }
    ChangeStamp.digest(rows.size, rows.inspect, load.inspect)
  end

  # Spec 036, S3 (supersedes spec 023's busy/free): "free" with nothing in progress, "working" below the limit, "busy"
  # only at the limit or over it. The count is the agent's load over all users and spaces (R3).
  def state(activities, capacity)
    return "busy" if capacity[:full]

    capacity[:running].positive? || activities.present? ? "working" : "free"
  end

  # "free · 0/6 in progress", "2/6 in progress", "busy · 6/6 in progress".
  def headline(state, capacity)
    { "free" => "free · ", "busy" => "busy · " }[state].to_s + capacity[:label]
  end

  # "2/6 in progress · World review · step 2/4: Collect evidence · +1 more" (G2, R5); the activities are the user's own.
  def label(activities, capacity)
    text = headline(state(activities, capacity), capacity)
    return text if activities.blank?

    "#{text} · #{activities.first.label}#{" · +#{activities.size - 1} more" if activities.size > 1}"
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
      next unless %w[director verifier deputy].include?(r.role) # spec 043: the deputy director too
      next if list.any? { |agent, _, _| agent.id == r.agent_id }

      list << [ r.agent, r.role == "deputy" ? "Deputy director" : r.role.capitalize, false ]
    end
    list
  end

  # Spec 036, R3/S6: { agent_id => running steps } over all users and spaces — the count the scheduler starts by.
  # Only totals: which runs they are stays with the rules above. One query.
  def running_counts(agent_ids)
    TaskRun.occupying(agent_ids).group(:agent_id).count
  end

  # Spec 036, S3: { running: 3, limit: 6, full: false, label: "3/6 in progress" }; full (busy) at the limit or over it.
  def capacity(running, limit)
    { running: running, limit: limit, full: running >= limit, label: "#{running}/#{limit} in progress" }
  end

  # Spec 023 contract: { stamp, agents: [{ id, name, role, member, status, headline, label, show_dot, activities: […], capacity }] }.
  # `status`: free, working or busy (spec 036, S3); `headline` is its text with the count. `show_dot`: members always;
  # the director and verifier only while they run something (R11). Spec 036: `capacity` is the agent's load.
  def json(user, statuses = self.for(user))
    list = team(user)
    counts = running_counts(list.map { |agent, _, _| agent.id })
    agents = list.map do |agent, role, member|
      activities = statuses[agent.id] || []
      # The user's own running steps are among the counted ones; max() only covers a step ending between the queries.
      load = capacity([ counts[agent.id].to_i, activities.size ].max, agent.max_parallel_tasks)
      status = state(activities, load)
      { id: agent.id, name: agent.name, role: role, member: member, status: status, headline: headline(status, load),
        label: label(activities, load), show_dot: member || status != "free", activities: activities.map(&:as_json), capacity: load }
    end
    { stamp: stamp(user, statuses, counts), agents: agents }
  end
end
