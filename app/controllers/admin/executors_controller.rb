# Spec 008: admins add executors from presets, edit, enable/disable, check and delete them.
# Only these fields are accepted; the program, arguments and protocol come from Executor::PRESETS (Q3).
class Admin::ExecutorsController < Admin::BaseController
  before_action :set_executor, except: %i[new create]
  # A check holds a server thread for up to 10 seconds (R4), so checks are rate-limited (security analysis, F9).
  rate_limit to: 20, within: 1.minute, only: %i[check refresh_models], store: RATE_LIMIT_STORE,
             with: -> { redirect_to executors_path, alert: "Too many checks. Try again in a minute." }

  def new
    @executor = Executor.new(preset: params[:preset].presence_in(Executor::PRESETS.keys) || "claude_code")
  end

  def create
    @executor = Executor.new(executor_params)
    if @executor.save
      redirect_to executors_path, notice: "Executor #{@executor.name} added. Check it to see whether it answers."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @executor.update(executor_params)
      redirect_to executors_path, notice: "Executor #{@executor.name} updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    if @executor.destroy
      redirect_to executors_path, notice: "Executor #{@executor.name} deleted."
    else
      redirect_to edit_admin_executor_path(@executor), alert: "#{@executor.name} is used by agents; assign them another executor first."
    end
  end

  def check
    result = @executor.check!
    redirect_to executors_path, (result.ok ? :notice : :alert) => "#{@executor.name}: #{result.ok ? "answers" : "check failed"}."
  end

  # Spec 022, G3: read the tool's model list again; the forms offer it.
  def refresh_models
    result = @executor.refresh_models!
    message = result.ok ? "#{@executor.name}: #{result.models.size} models listed." : "#{@executor.name}: #{result.note}"
    redirect_to edit_admin_executor_path(@executor), (result.ok ? :notice : :alert) => message
  end

  private

  def set_executor
    @executor = Executor.find(params[:id])
  end

  def executor_params
    params.expect(executor: %i[name preset enabled base_url default_model effort extra_models notes])
  end
end
