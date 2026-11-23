# Spec 051, G2: the owner's groups of spaces — create, rename, delete (its spaces go out of every group), and order.
class SpaceGroupsController < ApplicationController
  rescue_from(ActiveRecord::RecordNotFound) { head :not_found }

  def create
    group = current_user.space_groups.new(name: params.dig(:space_group, :name))
    group.save ? redirect_to(spaces_path, notice: "Group added: #{group.name}.") : redirect_to(spaces_path, alert: group.errors.full_messages.to_sentence)
  end

  def update
    group = current_user.space_groups.find(params[:id])
    if group.update(name: params.dig(:space_group, :name))
      respond_to do |format|
        format.json { render json: { ok: true, name: group.name } }
        format.html { redirect_to spaces_path, notice: "Group renamed: #{group.name}." }
      end
    else
      respond_to do |format|
        format.json { render json: { ok: false, error: group.errors.full_messages.to_sentence }, status: :unprocessable_content }
        format.html { redirect_to spaces_path, alert: group.errors.full_messages.to_sentence }
      end
    end
  end

  def destroy
    group = current_user.space_groups.find(params[:id])
    group.destroy!
    redirect_to spaces_path, notice: "Group deleted: #{group.name}. Its spaces are now in “#{SpaceGroup::UNGROUPED}”."
  end

  def order
    SpaceGroup.arrange!(current_user, Array(params[:ids]))
    render json: { ok: true }
  end
end
