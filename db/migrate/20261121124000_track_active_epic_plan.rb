class TrackActiveEpicPlan < ActiveRecord::Migration[8.1]
  def up
    add_column :work_items, :active_step_from, :integer, default: 1, null: false

    # Retained steps from a legacy move or replan belong to the prior plan.
    return unless DataChange.table_exists?

    resets = DataChange.where(record_type: "WorkItem", action: "update")
                       .where("json_type(changeset, '$.space_id') IS NOT NULL OR json_extract(changeset, '$.state[1]') = 'new'")
                       .group(:record_id).maximum(:occurred_at)
    resets.each do |item_id, reset_at|
      position = select_value(<<~SQL).to_i
        SELECT MAX(position) FROM epic_steps
        WHERE work_item_id = #{Integer(item_id)} AND created_at <= #{connection.quote(reset_at)}
      SQL
      execute "UPDATE work_items SET active_step_from = #{position + 1} WHERE id = #{Integer(item_id)}"
    end
  end

  def down
    remove_column :work_items, :active_step_from
  end
end
