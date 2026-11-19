# Spec 002, G6: one-time password-change link, shown once to the admin.
class Admin::PasswordLinksController < Admin::BaseController
  def create
    @user = User.find(params[:user_id])
    @link = PasswordLink.issue!(user: @user, created_by: current_user)
    render :show, status: :created
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_user_path(@user), alert: e.record.errors.full_messages.to_sentence
  end
end
