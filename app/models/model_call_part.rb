# Spec 030, G1: a part's place in one call's prompt — section (0 is the master prompt), kind and order.
class ModelCallPart < ApplicationRecord
  self.changelog_skipped = true

  belongs_to :model_call
  belongs_to :trace_part
end
