# Spec 039: how much the director writes in its chat replies (text only; voice keeps its spoken rule, R3).
#   1 Krótko (default): at most 3 sentences or 3 short points.
#   2 Średnio: one short paragraph, or a short list where it helps.
#   3 Szczegółowo: a full explanation with context and reasons.
module ReplyLength
  LEVELS = { 1 => "Krótko", 2 => "Średnio", 3 => "Szczegółowo" }.freeze
  HINTS = {
    1 => "At most 3 sentences: the answer first, then what happens next.",
    2 => "One short paragraph, or a short list where it helps.",
    3 => "A full explanation with context and reasons."
  }.freeze
  DEFAULT = 1

  def self.valid?(level) = LEVELS.key?(level)
  def self.name(level) = LEVELS.fetch(level, LEVELS[DEFAULT])

  # G1, R5: the rule for the director's text reply; a request for detail in the latest message lengthens that reply only.
  def self.rule(level, username)
    what = case level
           when 2 then "one short paragraph, or a short list where it helps; leave out background #{username} did not ask for."
           when 3 then "a full explanation with the context and the reasons where they help; still no padding or repetition."
           else "at most 3 sentences or 3 short points. Give the answer first, then what happens next; no background, no restating what #{username} said, no closing summary."
           end
    "Reply length chosen by #{username}: #{name(level)} — #{what} " \
      "If #{username}'s latest message asks for detail or a full explanation, that one reply may be longer; the chosen length stays."
  end
end
