# Spec 011, G3/G4: the user's team — director, managers, members — and its org chart.
class TeamsController < ApplicationController
  def show
    @director = current_user.director_role
    @managers = current_user.team_roles.managers.includes(agent: :executor, members: { agent: :executor }).order(:id)
    @candidates = Agent.visible_to(current_user).includes(:executor).ordered
  end
end
