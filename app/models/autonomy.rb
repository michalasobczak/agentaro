# Spec 033: the autonomy slider — how often the director and the agents ask the owner.
#   1 Pytaj (Ask): clarifying questions before planning, the plan waits for approval, steps stop to ask.
#   2 Ważne pytaj (Ask about important things, default): steps ask only about important decisions.
#   3 Decyduj (Decide): nobody asks except for the always-ask list; agents pick their recommendation.
# A space's own level wins over the owner's default (R1). The always-ask list (G4) is in code and counts at every level.
module Autonomy
  LEVELS = { 1 => "Pytaj", 2 => "Ważne pytaj", 3 => "Decyduj" }.freeze
  HINTS = {
    1 => "Agents ask before planning, the plan waits for your approval, steps stop to ask when a decision matters.",
    2 => "Agents decide small things and write them down; they ask about important decisions.",
    3 => "Agents never ask except for the always-ask list; they pick their own recommendation and write it down."
  }.freeze
  DEFAULT = 2
  ALWAYS_ASK = [
    "sending, publishing or posting anything outside Agentaro (e-mail, messages, social media, websites)",
    "spending money or buying anything",
    "deleting or overwriting data outside the run's own folder",
    "pushing to a shared repository",
    "anything touching passwords, keys or tokens"
  ].freeze
  MAX_CLARIFYING = 3     # R2: clarifying questions per epic at level 1
  MAX_DECISIONS = 3      # decisions one step may raise before its answer is taken as it is
  DECISION_PREFIX = "AGENTARO-DECISION:"
  ASSUMED_PREFIX = "AGENTARO-ASSUMED:"

  def self.valid?(level) = LEVELS.key?(level)
  def self.level_for(space, user = space.user) = space&.autonomy_level || user.autonomy_level || DEFAULT
  def self.name(level) = LEVELS.fetch(level, LEVELS[DEFAULT])
  def self.always_ask_text = ALWAYS_ASK.map { |line| "- #{line}" }.join("\n")

  # G3, G4: what a step is told about asking, by level.
  def self.step_rules(level)
    ask = case level
          when 1 then "Your owner wants to be asked: when a decision matters for the result (scope, format, approach, anything you would otherwise guess), stop and ask with a decision line instead of guessing."
          when 3 then "Your owner wants you to decide: never ask, except for the always-ask list below. Choose what you would recommend, do the task, and write each choice down as an assumption line."
          else "Decide small things yourself and write each choice down as an assumption line. Ask with a decision line only about important decisions: costly, hard to undo, or a matter of your owner's taste — and always for the always-ask list below."
          end
    <<~RULES.chomp

      Asking your owner (autonomy level: #{name(level)}). #{ask}
      Always ask first, at every level, and never do it without an answer — these decisions always belong to your owner:
      #{always_ask_text}
      To ask, end your answer with exactly one line (JSON on one line), and do not do the part that needs the answer:
      #{DECISION_PREFIX} {"question": "...", "options": ["...", "..."], "recommended": "one of the options", "why": "one sentence", "important": true or false, "always_ask": true or false}
      For each choice you made yourself, add a line: #{ASSUMED_PREFIX} what you assumed, in one short sentence
      Write these lines in the language of the task.
    RULES
  end

  # R5: a decision line from a step is data; anything malformed is ignored. Returns a Hash or nil.
  def self.parse_decision(text)
    line = text.to_s.lines.reverse.find { |l| l.strip.start_with?(DECISION_PREFIX) } or return nil
    data = JSON.parse(line.strip.delete_prefix(DECISION_PREFIX).strip)
    return nil unless data.is_a?(Hash)

    question = data["question"].to_s.strip.truncate(500)
    options = Array(data["options"]).map { |o| o.to_s.strip.truncate(200) }.reject(&:empty?).uniq.first(4)
    return nil if question.empty? || options.size < 2

    recommended = data["recommended"].to_s.strip.truncate(200)
    recommended = options.first unless options.include?(recommended)
    { question: question, options: options, recommended: recommended, why: data["why"].to_s.strip.truncate(300).presence,
      important: data["important"] == true, always_ask: data["always_ask"] == true }
  rescue JSON::ParserError
    nil
  end

  def self.parse_assumptions(text)
    text.to_s.lines.filter_map { |l| l.strip.delete_prefix(ASSUMED_PREFIX).strip.truncate(300).presence if l.strip.start_with?(ASSUMED_PREFIX) }.uniq.first(10)
  end

  # Should a step's decision wait for the owner at this level?
  def self.ask_owner?(level, decision) = decision[:always_ask] || level == 1 || (level == 2 && decision[:important])
end
