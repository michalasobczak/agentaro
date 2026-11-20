# Spec 011, G3: adding and removing roles in the user's own team.
class TeamRolesController < ApplicationController
  rescue_from(ActiveRecord::RecordNotFound) { head :not_found }

  def create
    attrs = params.expect(team_role: %i[role agent_id parent_id role_text])
    role = current_user.team_roles.new(role: attrs[:role], role_text: attrs[:role_text],
                                       agent: Agent.visible_to(current_user).find_by(id: attrs[:agent_id]),
                                       parent: attrs[:parent_id].present? ? current_user.team_roles.find(attrs[:parent_id]) : nil)
    if role.save
      redirect_to team_path, notice: "#{role.agent.name} is now #{role.role == "member" ? "in #{role.parent.agent.name}'s team" : "a #{role.role}"}."
    else
      redirect_to team_path, alert: role.errors.full_messages.to_sentence
    end
  end

  def update
    role = current_user.team_roles.find(params[:id])
    role.update(role_text: params.dig(:team_role, :role_text)) ? redirect_to(team_path, notice: "Role saved.") : redirect_to(team_path, alert: role.errors.full_messages.to_sentence)
  end

  def destroy
    role = current_user.team_roles.find(params[:id])
    role.destroy!
    redirect_to team_path, notice: "#{role.agent.name} removed#{" with their team" if role.role == "manager" && role.members.any?}."
  end
end
