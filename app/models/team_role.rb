# Spec 011, G3: a user's team — one director, managers under it, members under each manager.
# One agent may hold several roles (Q5). Candidates are the user's private agents and shared agents.
class TeamRole < ApplicationRecord
  ROLES = %w[director manager member].freeze

  belongs_to :user
  belongs_to :agent
  belongs_to :parent, class_name: "TeamRole", optional: true # a member's manager
  has_many :members, class_name: "TeamRole", foreign_key: :parent_id, dependent: :destroy, inverse_of: :parent

  normalizes :role_text, with: ->(value) { value.to_s.strip.presence }

  validates :role, inclusion: { in: ROLES }
  validates :role_text, length: { maximum: 100 }
  validate :agent_visible_to_user
  validate :shape

  scope :directors, -> { where(role: "director") }
  scope :managers, -> { where(role: "manager") }

  private

  def agent_visible_to_user
    errors.add(:agent, "is not one of your agents or a shared agent") if agent && user && !Agent.visible_to(user).exists?(agent.id)
  end

  def shape
    case role
    when "director"
      errors.add(:base, "You already have a director") if TeamRole.where(user_id: user_id, role: "director").where.not(id: id).exists?
      errors.add(:parent, "must be empty") if parent
    when "manager"
      errors.add(:parent, "must be empty") if parent
      errors.add(:agent, "is already a manager") if TeamRole.where(user_id: user_id, role: "manager", agent_id: agent_id).where.not(id: id).exists?
    when "member"
      errors.add(:parent, "must be one of your managers") unless parent&.role == "manager" && parent.user_id == user_id
      errors.add(:agent, "is already in this manager's team") if parent && TeamRole.where(parent_id: parent.id, agent_id: agent_id).where.not(id: id).exists?
    end
  end
end
