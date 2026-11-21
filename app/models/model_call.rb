# Spec 030: one call of a model within a run — what it was sent (parts), what it answered, what it did (events) and
# what it cost. A run may make more than one call (the director's reply and its proposal pass).
class ModelCall < ApplicationRecord
  self.changelog_skipped = true

  belongs_to :task_run
  belongs_to :user, optional: true
  belongs_to :output_part, class_name: "TracePart", optional: true
  has_many :parts, -> { order(:position) }, class_name: "ModelCallPart", dependent: :destroy, inverse_of: :model_call

  scope :ordered, -> { order(:position) }

  def answer = output_part&.content

  # G1, R1: the prompt rebuilt from its parts, exactly as sent (with secrets replaced by a marker, R2).
  def prompt_text
    sections = parts.includes(:trace_part).group_by(&:section).sort.map { |_, list| list.map { |p| p.trace_part.content }.join(RunTrace::CHUNK) }
    return sections.join if layout == "legacy"

    system, *user = sections
    "#{system}#{AgentCall::PROMPT_SEPARATOR}#{user.join(joiner)}"
  end

  # G2: the events, compressed or not (G6).
  def event_list
    return [] if events.blank?

    JSON.parse(events_format == "zlib" ? Zlib::Inflate.inflate(events) : events)
  rescue JSON::ParserError, Zlib::Error
    []
  end

  def duration = duration_ms && duration_ms / 1000.0
end
