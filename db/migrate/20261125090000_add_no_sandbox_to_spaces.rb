# Spec 054, G1: a space whose steps, CI and server run without a sandbox; off by default.
class AddNoSandboxToSpaces < ActiveRecord::Migration[8.1]
  def change
    add_column :spaces, :no_sandbox, :boolean, default: false, null: false
  end
end
