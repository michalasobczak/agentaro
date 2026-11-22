# Spec 043, G4/G5: who does the director's work now. While the director's executor is at a reached usage limit, the
# deputy director answers (when one is chosen, available and not at a limit itself); otherwise nobody can, until the
# limit resets.
class DirectorRoute
  attr_reader :director

  def initialize(user, director, now: Time.current)
    @user, @director, @now = user, director, now
  end

  # When the director's tool is free again; nil when it is not at a limit.
  def limited_until = @limited_until ||= UsageLimit.until(@director&.executor, now: @now)

  def limited? = limited_until.present?

  # The deputy, when it can work now.
  def deputy
    return @deputy if defined?(@deputy)

    agent = @user.deputy_role&.agent
    @deputy = agent if agent&.usable? && agent.id != @director&.id && !UsageLimit.until(agent.executor, now: @now)
  end

  # The agent to call now: the director, the deputy while the director is at its limit, or nil (nobody can).
  def agent = limited? ? deputy : @director

  # The chat's mark on a deputy's answer (G4).
  def deputy_note(agent = deputy, until_at = limited_until)
    "#{agent.name}, the deputy director, answers: the director's #{@director.executor.label} is at its usage limit#{" until #{UsageLimit.clock(until_at, @now)}" if until_at}."
  end

  # G5: what the chat says when nobody can answer.
  def wait_note
    deputy_text = @user.deputy_role ? "the deputy director cannot answer now either" : "choose a deputy director on the Team page to talk meanwhile"
    "The director's #{@director.executor.label} is at its usage limit until #{UsageLimit.clock(limited_until, @now)}; #{deputy_text}."
  end
end
