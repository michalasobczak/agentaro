# Spec 031, G1: a core memory block — always in the prompt of its scope: the user's profile, a space's brief or an
# agent's playbook. Edited by the user on the Brain page (and, from spec 033, by the curator).
class MemoryBlock < ApplicationRecord
  SCOPES = %w[user space agent].freeze
  MAX = 2000

  belongs_to :user

  normalizes :content, with: ->(value) { value.to_s.gsub("\r\n", "\n").strip }
  validates :scope_type, inclusion: { in: SCOPES }
  validates :content, length: { maximum: MAX }
  validates :scope_id, presence: true, unless: -> { scope_type == "user" }
  validate :scope_is_own

  before_update { self.version += 1 if content_changed? }

  def self.for(user, scope_type, scope_id = nil)
    user.memory_blocks.find_or_initialize_by(scope_type: scope_type, scope_id: scope_type == "user" ? nil : scope_id)
  end

  def scope_record
    case scope_type
    when "space" then user.spaces.find_by(id: scope_id)
    when "agent" then Agent.find_by(id: scope_id)
    end
  end

  private

  def scope_is_own
    case scope_type
    when "space" then errors.add(:scope_id, "is not one of your spaces") unless user&.spaces&.exists?(scope_id)
    when "agent" then errors.add(:scope_id, "is not one of your agents") unless Brain.agent_ids(user).include?(scope_id)
    end
  end
end
