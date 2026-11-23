# Spec 053, G1: "Relaxed sandbox" — command-line agents may reach the web, open local ports, and get a Git repository
# made by Agentaro before a step; file rules stay. On by default (owner's choice).
class AddRelaxedSandboxToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :relaxed_sandbox, :boolean, null: false, default: true
  end
end
