# Specs 013/014: a user's space — a project space (with a goal it works towards) or a team space (no goal: it
# takes care of ongoing work, described in its description). Agents working on an epic see only its own space.
class Space < ApplicationRecord
  STATES = %w[active archived].freeze
  KINDS = %w[project team].freeze
  DEFAULT_NAME = "General"
  DEFAULT_DESCRIPTION = "Everything that does not belong to another space."

  belongs_to :user
  belongs_to :space_group, optional: true # spec 051
  has_many :ci_runs, -> { where(purpose: "ci") }, class_name: "TaskRun", dependent: :destroy # spec 052
  has_many :work_items, dependent: :restrict_with_error # spec 013, R5: only empty spaces can be deleted
  has_many :recurring_orders, dependent: :destroy # spec 034, R4: deleted with the space
  after_update_commit :pause_recurring_orders, if: -> { saved_change_to_state? && state == "archived" } # spec 034, R4
  after_update_commit(if: -> { saved_change_to_state? && state == "archived" && server_wanted }) { Ci::Server.stop!(self) } # spec 052, R5
  before_destroy { Ci::Server.stop_process(self) } # spec 052, R5
  after_destroy_commit { Brain.forget_scope(user_id, "space", id) } # spec 031: its brief and facts go with it

  normalizes :name, with: ->(value) { value.to_s.strip.presence }
  normalizes :goal, with: ->(value) { value.to_s.strip.presence }
  normalizes :description, with: ->(value) { value.to_s.strip.presence }
  normalizes :working_dir, with: ->(value) { value.to_s.strip.presence }

  before_validation { self.goal = nil if team? } # spec 014, R1: a team space has no goal
  before_create { self.position = (user.spaces.where(space_group_id: space_group_id).maximum(:position) || 0) + 1 unless position.to_i.positive? } # spec 051: a new space goes last

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { scope: :user_id, case_sensitive: false }
  validates :kind, inclusion: { in: KINDS }
  validates :autonomy_level, inclusion: { in: Autonomy::LEVELS.keys }, allow_nil: true # spec 033: nil = the owner's default
  validates :work_tempo, inclusion: { in: WorkTempo::LEVELS.keys }, allow_nil: true # spec 041: nil = the owner's default
  validates :goal, presence: { message: "is required for a project space" }, if: :project?
  validates :goal, length: { maximum: 2000 }
  validates :description, length: { maximum: 5000 }
  validates :state, inclusion: { in: STATES }
  # Owner fix (spec 051): checked when the folder is set — a folder that later disappears must not block moving
  # the space, or any other space saved with it.
  validate :working_dir_usable, if: -> { new_record? || will_save_change_to_working_dir? }
  validate :group_of_owner # spec 051, R1

  scope :active, -> { where(state: "active") }
  scope :ordered, -> { order(Arel.sql("CASE state WHEN 'active' THEN 0 ELSE 1 END"), Arel.sql("LOWER(name)")) }

  # Spec 051, G3, R2: into a group (nil: out of every group) at a 1-based place; both groups are renumbered densely.
  def place!(group, index)
    Space.transaction do
      group&.lock!
      reload # the saved place, not a stale copy (a stale position would not be written)
      old_group_id = space_group_id
      siblings = user.spaces.where(space_group_id: group&.id).where.not(id: id).order(:position, :id).to_a
      siblings.insert((index.to_i - 1).clamp(0, siblings.size), self)
      self.space_group = group
      siblings.each_with_index { |space, i| space.position = i + 1; space.save! if space.changed? }
      user.spaces.where(space_group_id: old_group_id).order(:position, :id).each_with_index { |s, i| s.update!(position: i + 1) unless s.position == i + 1 } if old_group_id != group&.id
    end
  end

  # Spec 018: folders agents of a space with a working folder may never read — Agentaro's storage, the runs of
  # other steps — and the working folders of all other spaces (of every user), except folders that contain this one.
  def self.protected_dirs = [ Rails.root.join("storage"), Pathname(Rails.application.config.x.runs_dir).dirname ].map { |p| File.expand_path(p.to_s) }

  def denied_dirs
    others = Space.where.not(working_dir: nil).where.not(id: id).distinct.pluck(:working_dir)
    others.reject! { |dir| working_dir == dir || working_dir.start_with?(dir.end_with?("/") ? dir : "#{dir}/") }
    (self.class.protected_dirs + others).uniq
  end

  # Spec 025: what deleting an archived space takes with it (for the confirmation, R2).
  def purge_counts
    runs = purge_runs
    { epics: work_items.count, running: runs.where(state: %w[queued running]).count }
  end

  STOP_WAIT = 10 # seconds a stopped step may take to end (R3)

  # Spec 025: deletes an archived space with its epics, their steps, calendar entries, runs and run folders.
  # Running steps are stopped first (R3); every row goes through callbacks, so the data changelog keeps it (R4).
  def purge!(wait: STOP_WAIT)
    raise ArgumentError, "only an archived space is deleted with its epics" if active?

    ActiveRecord::Base.uncached do
      runs = purge_runs
      runs.where(state: "queued").find_each { |run| run.update!(state: "skipped", error: "The space was deleted.", finished_at: Time.current) }
      running = runs.where(state: "running").pluck(:id)
      running.each { |id| RunControl.stop!(id) }
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + wait
      while TaskRun.where(id: running, state: "running").exists? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        sleep 0.1
      end

      run_ids = runs.pluck(:id)
      transaction do
        ChatMessage.where(task_run_id: run_ids).find_each { |message| message.update!(task_run: nil) }
        TaskRun.where(id: run_ids).find_each(&:destroy!)
        work_items.each do |item|
          item.tasks.find_each(&:destroy!)
          item.reload.destroy!
        end
        reload.destroy!
      end
      remove_run_folders(run_ids)
      TracePart.prune_orphans! # spec 030, R5: text only these runs used goes with them
    end
  end

  # The runs of the space's epics, including runs of their calendar entries (steps planned before spec 016).
  def purge_runs
    items = work_items.select(:id)
    TaskRun.where(work_item_id: items).or(TaskRun.where(task_id: Task.where(work_item_id: items).select(:id)))
  end

  def active? = state == "active"
  def project? = kind == "project"
  def team? = kind == "team"

  # What the space is for, in one line: a project's goal, or what a team space takes care of.
  def purpose = project? ? goal : description

  # Spec 014, G3: how prompts describe the space.
  def purpose_line
    project? ? "project space; goal: #{goal}" : "team space (no goal); takes care of: #{description.presence || "-"}"
  end

  # Where an epic goes when nothing says which space: the only active space, or a new "General" team space (not
  # saved yet — it is saved with the epic). Nil when there are several active spaces, or only archived ones.
  def self.default_for(user)
    active = user.spaces.active.to_a
    return active.first if active.one?
    return nil if active.many? || user.spaces.exists?(name: DEFAULT_NAME)

    user.spaces.new(name: DEFAULT_NAME, kind: "team", description: DEFAULT_DESCRIPTION)
  end

  private

  def group_of_owner
    errors.add(:space_group, "is not one of your groups") if space_group && space_group.user_id != user_id
  end


  # R5: only <runs dir>/<run id>, a number, inside Agentaro's runs folder.
  def remove_run_folders(run_ids)
    root = File.expand_path(Rails.application.config.x.runs_dir.to_s)
    run_ids.each do |id|
      folder = File.join(root, Integer(id).to_s)
      FileUtils.rm_rf(folder) if File.dirname(folder) == root && File.directory?(folder) && !File.symlink?(folder)
    end
  end

  # Spec 018, R1: an absolute path to an existing folder, stored resolved; never "/", Agentaro's storage or the runs.
  def working_dir_usable
    return if working_dir.blank?
    return errors.add(:working_dir, "must be an absolute path, e.g. /Users/you/Code/project") unless working_dir.start_with?("/")
    return errors.add(:working_dir, "does not exist or is not a folder") unless File.directory?(working_dir)

    self.working_dir = File.realpath(working_dir)
    return errors.add(:working_dir, "cannot be the whole disk") if working_dir == "/"

    if self.class.protected_dirs.any? { |dir| working_dir == dir || working_dir.start_with?("#{dir}/") }
      errors.add(:working_dir, "cannot be Agentaro's storage or runs folder")
    end
  end

  private def pause_recurring_orders = recurring_orders.active.find_each { |order| order.update!(state: "paused", note: "Paused: the space was archived.") }
end
