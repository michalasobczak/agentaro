# Spec 031, G1: a core memory block — always in the prompt of its scope: the user's profile, a space's brief or an
# agent's playbook. Edited by the user on the Brain page (and, from spec 101, by the curator).
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

  # Fix (2026-11-21, found with spec 039): built outside the user's association, so a later user.update! in the same
  # run does not autosave an empty block (two of them broke the unique index and the director's answer).
  def self.for(user, scope_type, scope_id = nil)
    find_or_initialize_by(user_id: user.id, scope_type: scope_type, scope_id: scope_type == "user" ? nil : scope_id)
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
