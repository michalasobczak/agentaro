# Spec 011, G3/G4, corrected by spec 012: the user's team — the director and its members — and its org chart.
class TeamsController < ApplicationController
  def show
    @director = current_user.director_role
    @members = current_user.team_roles.members.includes(agent: :executor).order(:id)
    @candidates = Agent.visible_to(current_user).includes(:executor).ordered
  end
end
