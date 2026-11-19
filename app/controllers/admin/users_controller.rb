# Spec 002, G5: user management. Web-created accounts are regular users; they set their first password
# through a one-time link. Admins are created on the command line.
class Admin::UsersController < Admin::BaseController
  before_action :set_user, except: %i[index new create]

  def index
    @users = User.order(:username)
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(username: params.dig(:user, :username), role: "user", otp_required: params.dig(:user, :otp_required) == "1")
    if @user.save
      @link = PasswordLink.issue!(user: @user, created_by: current_user)
      render "admin/password_links/show", status: :created
    else
      render :new, status: :unprocessable_content
    end
  end

  def show
  end

  def update
    if @user.update(params.expect(user: %i[role active otp_required]))
      redirect_to admin_user_path(@user), notice: "User updated."
    else
      flash.now[:alert] = @user.errors.full_messages.to_sentence
      render :show, status: :unprocessable_content
    end
  end

  def reset_totp
    @user.reset_otp!
    redirect_to admin_user_path(@user), notice: "Authenticator reset. #{@user.otp_required? ? "The user sets up a new one at next sign-in." : ""}".strip
  end

  def revoke_sessions
    @user.sessions.find_each(&:destroy)
    redirect_to admin_user_path(@user), notice: "All sessions revoked."
  end

  private

  def set_user
    @user = User.find(params[:id])
  end
end
