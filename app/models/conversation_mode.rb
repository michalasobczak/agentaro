# Spec 046: how the conversation with the director flows. Naturalna makes the director talk like a person in a
# conversation (G2), the voice livelier (G3) and fills a long silence with a short acknowledgement (G4). It changes
# how things are said, never what is done (R1).
module ConversationMode
  LEVELS = { 1 => "Zwykła", 2 => "Naturalna" }.freeze
  HINTS = {
    1 => "As before: the director's replies follow only the reply length and the style.",
    2 => "Like talking to a person: short turns, no lists or ids, one question at most; a livelier voice."
  }.freeze
  DEFAULT = 2
  NATURAL = 2

  # G4: short phrases the voice says when the director needs a moment; their sound is made once and kept.
  ACKNOWLEDGEMENTS = {
    "pl" => [ "Już sprawdzam.", "Chwilka.", "Moment, patrzę." ],
    "en" => [ "Let me check.", "One moment.", "Just a second." ]
  }.freeze

  def self.valid?(level) = LEVELS.key?(level)
  def self.name(level) = LEVELS.fetch(level, LEVELS[DEFAULT])
  def self.natural?(user) = user&.conversation_mode == NATURAL
  def self.acknowledgement?(text) = ACKNOWLEDGEMENTS.values.flatten.include?(text.to_s)

  # G2: the director's conversational rule; the style (spec 041) still sets the words.
  def self.rule(username, detailed: false)
    turns = detailed ? "Say as much as the matter needs, but as talk, not as a report." : "Keep each turn to 1–3 sentences unless #{username} asks for detail."
    <<~RULE.squish
      Conversation mode chosen by #{username}: #{name(NATURAL)} — talk like a person in a conversation, not like a report.
      #{turns} React to what #{username} just said before you add anything. No lists, headings, ids or quoted titles unless
      #{username} asks for them or the matter truly needs them; name things the way people do. Say times, dates and numbers
      the way people say them. At most one question, at the end. No empty praise such as "Świetne pytanie!" and no
      announcing what you will say; vary how you start.
    RULE
  end
end
