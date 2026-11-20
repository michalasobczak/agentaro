# Owner fix after spec 010: a short fingerprint of what a page shows, so the page can ask "has anything
# changed?" and reload only then (auto refresh of the calendar and task pages).
module ChangeStamp
  module_function

  # Everything the calendar of `user` shows: visible tasks, their exceptions and runs, and agents' names.
  def calendar(user)
    tasks = Task.visible_to(user)
    ids = tasks.select(:id)
    digest(tasks.count, tasks.maximum(:updated_at),
           TaskException.where(task_id: ids).count, TaskException.where(task_id: ids).maximum(:updated_at),
           TaskRun.where(task_id: ids).count, TaskRun.where(task_id: ids).maximum(:updated_at),
           Agent.visible_to(user).maximum(:updated_at), user.work_items.maximum(:updated_at), user.spaces.maximum(:updated_at), # spec 013: epics
           EpicStep.where(work_item_id: user.work_items.select(:id)).maximum(:updated_at)) # spec 016: steps
  end

  # Spec 011: chat, list and management runs of the user.
  def management(user)
    runs = TaskRun.where(user: user)
    digest(user.chat_messages.count, user.chat_messages.maximum(:updated_at), user.work_items.count, user.work_items.maximum(:updated_at),
           runs.count, runs.maximum(:updated_at), Task.where(work_item_id: user.work_items.select(:id)).maximum(:updated_at),
           TaskRun.where(task_id: Task.where(work_item_id: user.work_items.select(:id)).select(:id)).maximum(:updated_at),
           EpicStep.where(work_item_id: user.work_items.select(:id)).maximum(:updated_at))
  end

  def run(run) = digest(run.state, run.updated_at)

  def task(task)
    digest(task.updated_at, task.exceptions.count, task.runs.count, task.runs.maximum(:updated_at), task.agent&.updated_at)
  end

  def digest(*parts) = Digest::SHA256.hexdigest(parts.map { |p| p.respond_to?(:utc) ? p.utc.iso8601(6) : p.to_s }.join("|"))[0, 16]
end
