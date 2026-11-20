# Spec 018: a space may have a working folder on the host; its steps run there.
class AddWorkingDirToSpaces < ActiveRecord::Migration[8.1]
  def change
    add_column :spaces, :working_dir, :string
  end
end
