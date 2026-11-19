# Spec 004: one create, update or delete of application data.
# `changeset` holds JSON: { "field" => [before, after] }, sensitive values replaced by "[FILTERED]".
class DataChange < AuditRecord
  include HashChained

  RETENTION = 3.months

  def changes_hash = JSON.parse(changeset)
end
