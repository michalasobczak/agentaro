# Spec 011, G3, corrected by spec 012: a user's team — one director and its members, each member with a role
# text. One agent may hold both roles (spec 011, Q5). Candidates are the user's private agents and shared agents.
class TeamRole < ApplicationRecord
  ROLES = %w[director member].freeze

  belongs_to :user
  belongs_to :agent

  normalizes :role_text, with: ->(value) { value.to_s.strip.presence }

  validates :role, inclusion: { in: ROLES }
  validates :role_text, length: { maximum: 100 }
  validate :agent_visible_to_user
  validate :one_per_role

  scope :directors, -> { where(role: "director") }
  scope :members, -> { where(role: "member") }

  private

  def agent_visible_to_user
    errors.add(:agent, "is not one of your agents or a shared agent") if agent && user && !Agent.visible_to(user).exists?(agent.id)
  end

  def one_per_role
    others = TeamRole.where(user_id: user_id, role: role).where.not(id: id)
    if role == "director"
      errors.add(:base, "You already have a director") if others.exists?
    elsif others.exists?(agent_id: agent_id)
      errors.add(:agent, "is already in your team")
    end
  end
end
