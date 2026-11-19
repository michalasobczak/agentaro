# Spec 003: one HTTP request.
class AuditEvent < AuditRecord
  include HashChained

  RETENTION = 3.months
end
