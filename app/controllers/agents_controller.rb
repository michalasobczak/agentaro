# Spec 009: agents. Users manage their private agents; admins also manage shared ones (Q1).
# Other users' private agents do not exist for anyone else (404); shared agents are read-only for users (403).
class AgentsController < ApplicationController
  before_action :set_agent, except: %i[index new create]
  before_action :require_editable, only: %i[edit update destroy]

  def index
    agents = Agent.visible_to(current_user).includes(:executor).ordered
    @private_agents = agents.select(&:private?)
    @shared_agents = agents.select(&:shared?)
  end

  def show
    redirect_to edit_agent_path(@agent) if @agent.editable_by?(current_user)
  end

  def new
    @agent = current_user.agents.new(kind: params[:kind] == "shared" && current_user.admin? ? "shared" : "private")
  end

  def create
    @agent = current_user.agents.new(agent_params)
    @agent.kind = params.dig(:agent, :kind) == "shared" && current_user.admin? ? "shared" : "private" # R2
    if @agent.save
      redirect_to agents_path, notice: "Agent #{@agent.name} created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @agent.update(agent_params)
      redirect_to agents_path, notice: "Agent #{@agent.name} saved."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @agent.destroy!
    redirect_to agents_path, notice: "Agent #{@agent.name} deleted; its tasks stay without an agent."
  end

  private

  def set_agent
    @agent = Agent.visible_to(current_user).find(params[:id])
  end

  def require_editable
    render "shared/forbidden", status: :forbidden, locals: { reason: "Only admins change shared agents." } unless @agent.editable_by?(current_user)
  end

  # The executor must be one that exists; disabled executors may stay on an agent but are not offered for a new choice.
  def agent_params
    attrs = params.expect(agent: %i[name description master_prompt executor_id model effort enabled])
    if attrs[:executor_id].present? && attrs[:executor_id].to_s != @agent&.executor_id.to_s
      attrs[:executor_id] = Executor.where(enabled: true).find_by(id: attrs[:executor_id])&.id
    end
    attrs
  end
end
