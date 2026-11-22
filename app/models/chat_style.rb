# Spec 041, G3: how the director talks in the chat, written and spoken (R2). Independent of the reply length (R3).
#   1 Dziecko: simple words, short sentences, no jargon.
#   2 Dorosły (default): plain language, technical terms only when needed and explained.
#   3 Inżynier: precise technical language.
module ChatStyle
  LEVELS = { 1 => "Dziecko", 2 => "Dorosły", 3 => "Inżynier" }.freeze
  HINTS = {
    1 => "Simple words and short sentences, no technical terms; everyday comparisons.",
    2 => "Plain language; technical terms only when needed, explained in a few words.",
    3 => "Precise technical language: files, commands, models and numbers, no simplifications."
  }.freeze
  DEFAULT = 2

  def self.valid?(level) = LEVELS.key?(level)
  def self.name(level) = LEVELS.fetch(level, LEVELS[DEFAULT])

  def self.rule(level, username)
    what = case level
           when 1 then "talk as to a child of about ten: simple everyday words, short sentences, no technical terms, jargon or abbreviations; where it helps, a comparison from everyday life."
           when 3 then "precise technical language for an engineer: name the files, commands, models, states and numbers; no simplifications or analogies."
           else "plain language for an adult who is not a specialist; use a technical term only when it is needed, and explain it in a few words."
           end
    "Conversation style chosen by #{username}: #{name(level)} — #{what} The style sets your words, not the length of your reply."
  end
end
