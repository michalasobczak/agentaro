# Tamper evidence for audit tables (specs 003 G3/G4, 004 G4).
#
# Each row stores the hash of the previous row and SHA-256(previous hash + its own content).
# Editing or deleting a row breaks the chain from that row on. Pruning keeps the chain verifiable:
# the hash of the newest pruned row is stored as the chain anchor.
#
# Rows are appended only through append!; the application has no other write path (spec 003 S4).
module HashChained
  extend ActiveSupport::Concern

  GENESIS = "0" * 64

  included do
    class_attribute :chain_lock, instance_writer: false, default: Mutex.new
    before_update { raise ActiveRecord::ReadOnlyRecord, "#{self.class.name} rows are append-only" }
    before_destroy { raise ActiveRecord::ReadOnlyRecord, "#{self.class.name} rows are append-only" }
  end

  class_methods do
    def chain_name = table_name

    def hashed_columns
      column_names - %w[id prev_hash row_hash]
    end

    def append!(attributes)
      chain_lock.synchronize do
        transaction do
          row = new(attributes)
          row.occurred_at = (row.occurred_at || Time.current).utc.floor(6) # stored precision: microseconds
          row.prev_hash = order(:id).last&.row_hash || anchor_hash
          row.row_hash = row.compute_hash
          row.save!
          row
        end
      end
    end

    # Returns nil when the chain is intact, otherwise the first row that does not verify.
    def first_broken_row
      expected = anchor_hash
      order(:id).find_each do |row|
        return row if row.prev_hash != expected || row.row_hash != row.compute_hash

        expected = row.row_hash
      end
      nil
    end

    # Removes rows older than `before` (retention) and moves the chain anchor forward.
    def prune!(before:)
      chain_lock.synchronize do
        transaction do
          boundary = where(occurred_at: ...before).order(:id).last
          next 0 unless boundary

          count = where(id: ..boundary.id).delete_all
          anchor = ChainAnchor.find_or_initialize_by(chain: chain_name)
          anchor.update!(anchor_hash: boundary.row_hash, pruned_before: before)
          count
        end
      end
    end

    def anchor_hash
      ChainAnchor.find_by(chain: chain_name)&.anchor_hash || GENESIS
    end
  end

  def compute_hash
    values = self.class.hashed_columns.map { |column| canonical(self[column]) }
    OpenSSL::Digest::SHA256.hexdigest([ prev_hash, *values ].to_json)
  end

  private

  def canonical(value)
    case value
    when Time, ActiveSupport::TimeWithZone then value.utc.iso8601(6)
    when Float then format("%.3f", value)
    else value
    end
  end
end
