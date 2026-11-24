# Spec 052, owner change 2026-11-24, R7: every server process Agentaro started for a space, until it is seen gone.
class AddServerProcessesToSpaces < ActiveRecord::Migration[8.1]
  def change
    add_column :spaces, :server_processes, :text
  end
end
