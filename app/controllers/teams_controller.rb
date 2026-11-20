# Spec 011, G3/G4, corrected by spec 012: the user's team — the director and its members — and its org chart.
class TeamsController < ApplicationController
  def show
    @director = current_user.director_role
    @verifier = current_user.verifier_role # spec 019
    @members = current_user.team_roles.members.includes(agent: :executor).order(:id)
    @candidates = Agent.visible_to(current_user).includes(:executor).ordered
    @team_status = AgentStatus.json(current_user) # spec 023, G3
    @statuses = @team_status[:agents].index_by { |a| a[:id] }
  end

  # Spec 023, G5: polled by team_status.js every 5 s while the Team page is visible. Only the viewer's own runs (R8).
  def status
    render json: AgentStatus.json(current_user)
  end
end
