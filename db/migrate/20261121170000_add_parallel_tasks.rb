# Spec 036: how many steps an agent may run at the same time (R1), and the process of a run, so a restart can confirm
# that an executor which outlived the server has ended before its slot is freed (R5).
class AddParallelTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :agents, :max_parallel_tasks, :integer, default: 6, null: false
    add_column :task_runs, :pid, :integer
  end
end
