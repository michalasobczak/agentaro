# Spec 030, G1: one distinct piece of prompt or answer text, stored once and shared by every call that used it.
class TracePart < ApplicationRecord
  self.changelog_skipped = true # derived from the run, which is in the data changelog; R5: deleted with it

  has_many :model_call_parts, dependent: :restrict_with_exception

  def self.digest_of(content) = Digest::SHA256.hexdigest(content)

  # The part with this content, created when new.
  def self.for(content)
    digest = digest_of(content)
    find_by(digest: digest) || create!(digest: digest, content: content, bytes: content.bytesize)
  rescue ActiveRecord::RecordNotUnique
    find_by!(digest: digest)
  end

  # R5: parts no call uses any more (prompt parts or answers) are deleted.
  def self.prune_orphans!
    used = ModelCallPart.select(:trace_part_id)
    answers = ModelCall.where.not(output_part_id: nil).select(:output_part_id)
    orphans = where.not(id: used).where.not(id: answers)
    count = 0
    orphans.find_each { |part| part.destroy! && count += 1 }
    count
  end
end
