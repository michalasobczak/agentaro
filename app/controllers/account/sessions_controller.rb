# Spec 002, G3: a user's own sessions (signed-in browsers), with revocation.
class Account::SessionsController < ApplicationController
  def index
    @sessions = current_user.sessions.order(created_at: :desc)
  end

  def destroy
    record = current_user.sessions.find(params[:id])
    if record == Current.session
      terminate_session
      redirect_to new_session_path, notice: "Signed out."
    else
      record.destroy
      redirect_to account_sessions_path, notice: "Session revoked."
    end
  end

  def others
    current_user.sessions.where.not(id: Current.session.id).find_each(&:destroy)
    redirect_to account_sessions_path, notice: "Signed out everywhere else."
  end
end
