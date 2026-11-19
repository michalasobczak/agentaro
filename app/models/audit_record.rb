# Base for records in the separate audit database (specs 003, 004).
# Not an ApplicationRecord, so audit rows are never recorded in the data changelog themselves.
class AuditRecord < ActiveRecord::Base
  self.abstract_class = true

  connects_to database: { writing: :audit, reading: :audit }
end
