# Spec 022: what the model picker (model_picker.js) needs — the choices per executor, as JSON in a data attribute.
module ModelsHelper
  def model_list_entry(executor)
    { models: executor.model_choices, efforts: executor.efforts, default: executor.default_model, default_effort: executor.effort }
  end

  def model_lists_json(executors) = executors.to_h { |e| [ e.id.to_s, model_list_entry(e) ] }.to_json

  # The last "Check model" result kept on an agent or executor (G4).
  def model_check_status(record)
    return tag.span("Not checked yet.", class: "muted small", data: { model_check_result: "" }) unless record&.model_checked_at

    tag.span(class: "small model-check-result", data: { model_check_result: "", state: record.model_check_ok? ? "ok" : "bad" }) do
      safe_join([ record.model_check_ok? ? "✓ " : "✗ ", record.model_check_output, " ",
                  tag.span("(#{l record.model_checked_at, format: :short})", class: "muted") ])
    end
  end
end
