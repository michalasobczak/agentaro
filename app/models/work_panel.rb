# Spec 027: what the panel beside the director chat shows — each active space, its epics that are new, planned,
# running or blocked, and their steps with their states. Built once for the server's page and for the JSON poll.
class WorkPanel
  ORDER = %w[running blocked planned new].freeze # board states, the most urgent first
  MAX_EPICS = 20 # per space

  def self.for(user) = new(user).to_h

  def initialize(user) = @user = user

  def to_h
    spaces = @user.spaces.active.order(Arel.sql("LOWER(name)")).to_a
    items = @user.work_items.where(space_id: spaces.map(&:id), state: %w[new planned blocked])
                 .includes(:epic_steps, epic_steps: :agent).to_a.group_by(&:space_id)
    { spaces: spaces.map { |space| space_h(space, items[space.id] || []) } }
  end

  private

  def space_h(space, items)
    sorted = items.sort_by { |i| [ ORDER.index(i.board_state) || 9, i.position.to_i, i.id ] }.first(MAX_EPICS)
    { id: space.id, name: space.name, url: helpers.space_path(space), epics: sorted.map { |item| epic_h(item) } }
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
