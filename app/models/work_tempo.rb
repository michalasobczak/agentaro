# Spec 041, G4: how finely the director splits work into steps. A space's own tempo wins over the owner's (G5, R1).
#   1 Dokładnie: smaller steps, the last one checks the work.
#   2 Normalnie (default): as before.
#   3 Turbo: exactly 1 step for 1 member, no clarifying questions (R5, R6).
module WorkTempo
  LEVELS = { 1 => "Dokładnie", 2 => "Normalnie", 3 => "Turbo" }.freeze
  HINTS = {
    1 => "Smaller steps; the last step checks the work (tests, a review).",
    2 => "The director splits the work as the task needs.",
    3 => "One step for one agent, no clarifying questions: fastest."
  }.freeze
  DEFAULT = 2
  TURBO = 3

  def self.valid?(level) = LEVELS.key?(level)
  def self.level_for(space, user = space.user) = space&.work_tempo || user.work_tempo || DEFAULT
  def self.name(level) = LEVELS.fetch(level, LEVELS[DEFAULT])
  def self.turbo?(space, user) = level_for(space, user) == TURBO

  # R4: the planning rule (planning and the director's re-plan after a failed step).
  def self.plan_rule(level)
    case level
    when 1
      "Tempo: #{name(1)}. Split the work into small steps, each with one clear result that can be checked. " \
        "The last step checks the work against the goal: it runs the tests, reviews the result or compares it with what was asked. " \
        "Where another member has the right skills, give that check to a member other than the one who did the work."
    when TURBO
      "Tempo: #{name(TURBO)}. Plan exactly 1 step, for the one member best fitted for the whole task; it does all the work in one go, quickly. " \
        "Do not ask clarifying questions: decide yourself and list what you assumed in \"assumptions\"."
    else
      "Tempo: #{name(2)}. Split the work into as many steps as it needs."
    end
  end
end
