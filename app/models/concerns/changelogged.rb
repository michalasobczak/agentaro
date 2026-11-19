# Spec 004: records every create, update and delete of application data in DataChange.
#
# Rows are written after the transaction commits (R1), so rolled-back changes leave no trace.
# Sensitive fields stay visible as changed, with values replaced by "[FILTERED]" (G3).
# A failure to write the changelog is logged and does not undo the committed change (accepted, Q3).
module Changelogged
  extend ActiveSupport::Concern

  included do
    # Columns whose values are too long for the changelog: recorded as "[N characters]" (spec 010).
    class_attribute :changelog_summarized, default: []

    after_create_commit { record_data_change("create", saved_changes) }
    after_update_commit { record_data_change("update", saved_changes.except("updated_at")) }
    after_destroy_commit { record_data_change("destroy", attributes.transform_values { |value| [ value, nil ] }) }
  end

  private

  def record_data_change(action, changes)
    return if changes.blank?

    DataChange.append!(
      request_id: Current.request_id,
      actor: Current.actor_label,
      record_type: self.class.name,
      record_id: id,
      action: action,
      changeset: Changelogged.filter.filter(summarize_long_values(changes)).to_json
    )
  rescue StandardError => e
    Rails.logger.error("[changelog] could not record #{action} of #{self.class.name}##{id}: #{e.class}: #{e.message}")
  end

  def summarize_long_values(changes)
    return changes if changelog_summarized.empty?

    changes.to_h.to_h do |key, values|
      next [ key, values ] unless changelog_summarized.include?(key.to_s)

      [ key, Array(values).map { |v| v.nil? ? nil : "[#{v.to_s.length} characters]" } ]
    end
  end

  def self.filter
    @filter ||= ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
  end
end
