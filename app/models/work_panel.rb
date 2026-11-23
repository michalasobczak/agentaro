# Spec 027: what the panel beside the director chat shows — each active space, its epics that are new, planned,
# running or blocked, and their steps with their states. Built once for the server's page and for the JSON poll.
class WorkPanel
  ORDER = %w[running blocked planned new].freeze # board states, the most urgent first
  MAX_EPICS = 20 # per space
  CI_DOTS = { "ok" => "ok", "failed_build" => "bad", "failed_test" => "bad", "error" => "bad", "running" => "busy", "queued" => "busy" }.freeze # spec 052

  def self.for(user) = new(user).to_h

  def initialize(user) = @user = user

  def to_h
    groups = SpaceGroup.layout(@user, @user.spaces.active.to_a).reject { |_, spaces| spaces.empty? } # spec 051: the owner's groups and order
    spaces = groups.flat_map(&:last)
    items = @user.work_items.where(space_id: spaces.map(&:id), state: %w[new planned blocked])
                 .includes(:epic_steps, epic_steps: :agent).to_a.group_by(&:space_id)
    { groups: groups.map { |group, list| { id: group&.id, name: group&.name, spaces: list.map { |space| space_h(space, items[space.id] || []) } } },
      spaces: spaces.map { |space| space_h(space, items[space.id] || []) } }
  end

  private

  def space_h(space, items)
    sorted = items.sort_by { |i| [ ORDER.index(i.board_state) || 9, i.position.to_i, i.id ] }.first(MAX_EPICS)
    { id: space.id, name: space.name, url: helpers.space_path(space), epics: sorted.map { |item| epic_h(item) },
      ci: CI_DOTS[space.ci_state], server: (space.server_state if space.server_wanted || space.server_state == "down") } # spec 052, G5
  end

  def epic_h(item)
    steps = item.epic_steps.select { |s| s.position >= item.active_step_from.to_i }
    { id: item.id, title: item.title, state: item.board_state, url: helpers.work_item_path(item),
      paused: (item.pausing? ? "pausing" : "paused" if item.paused?), # spec 048
      pause_url: (helpers.public_send(item.paused? ? :resume_work_item_path : :pause_work_item_path, item) if item.state == "planned"),
      steps: steps.map { |s| { id: s.id, position: s.position, title: s.title, state: s.state, agent: s.agent&.name,
                         note: (s.retry_note if s.state == "queued") } } } # spec 032, G4
  end

  def helpers = Rails.application.routes.url_helpers
end
