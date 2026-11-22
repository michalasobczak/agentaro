# Spec 011, G3, corrected by spec 012: a user's team — one director and its members, each member with a role
# text. One agent may hold both roles (spec 011, Q5). Candidates are the user's private agents and shared agents.
class TeamRole < ApplicationRecord
  ROLES = %w[director member verifier deputy].freeze # spec 019: one verifier; spec 043: one deputy director

  belongs_to :user
  belongs_to :agent

  normalizes :role_text, with: ->(value) { value.to_s.strip.presence }

  validates :role, inclusion: { in: ROLES }
  validates :role_text, length: { maximum: 100 }
  validate :agent_visible_to_user
  validate :one_per_role
  validate :deputy_apart_from_director

  scope :directors, -> { where(role: "director") }
  scope :members, -> { where(role: "member") }
  scope :verifiers, -> { where(role: "verifier") }
  scope :deputies, -> { where(role: "deputy") }

  private

  def agent_visible_to_user
    errors.add(:agent, "is not one of your agents or a shared agent") if agent && user && !Agent.visible_to(user).exists?(agent.id)
  end

  # Spec 043, R4: the deputy answers when the director's tool is at its limit, so it must be another agent on another
  # executor; it is not the verifier either.
  def deputy_apart_from_director
    roles = TeamRole.where(user_id: user_id).where.not(id: id).includes(:agent)
    if role == "deputy" && agent
      director = roles.find { |r| r.role == "director" }&.agent
      errors.add(:agent, "is your director; choose another agent") if director&.id == agent.id
      errors.add(:agent, "runs on the director's executor and would hit the same limit") if director && director.id != agent.id && director.executor_id == agent.executor_id
      errors.add(:agent, "is your verifier; choose another agent") if roles.any? { |r| r.role == "verifier" && r.agent_id == agent.id }
    elsif %w[director verifier].include?(role) && agent && roles.any? { |r| r.role == "deputy" && r.agent_id == agent.id }
      errors.add(:agent, "is your deputy director; choose another agent")
    end
  end

  def one_per_role
    others = TeamRole.where(user_id: user_id, role: role).where.not(id: id)
    if %w[director verifier deputy].include?(role)
      errors.add(:base, "You already have a #{role}") if others.exists?
    elsif others.exists?(agent_id: agent_id)
      errors.add(:agent, "is already in your team")
    end
  end
end
