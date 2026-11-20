# Spec 008: an AI tool Agentaro can use — a CLI on the host (logged in there, e.g. a subscription) or a
# local HTTP API that needs no token (Q2).
#
# What runs is decided only by PRESETS in code (Q3): the web chooses a preset, never a program,
# arguments or protocol.
class Executor < ApplicationRecord
  Preset = Data.define(:key, :label, :kind, :program, :version_args, :protocol, :default_url) do
    def cli? = kind == "cli"
    def api? = kind == "api"
    # Spec 010, Q3: tools not installed on the owner's host cannot be tested, so they do not run yet.
    def runnable? = !%w[gemini_cli grok_cli].include?(key)
  end

  PRESETS = [
    Preset.new("claude_code", "Claude Code", "cli", "claude", [ "--version" ], nil, nil),
    Preset.new("codex", "Codex", "cli", "codex", [ "--version" ], nil, nil),
    Preset.new("gemini_cli", "Gemini CLI", "cli", "gemini", [ "--version" ], nil, nil),
    Preset.new("grok_cli", "Grok CLI", "cli", "grok", [ "--version" ], nil, nil),
    Preset.new("ollama_cli", "Ollama (CLI)", "cli", "ollama", [ "--version" ], nil, nil),
    Preset.new("lm_studio_cli", "LM Studio (CLI)", "cli", "lms", [ "--version" ], nil, nil),
    Preset.new("ollama_api", "Ollama (API)", "api", nil, nil, "ollama", "http://localhost:11434"),
    Preset.new("lm_studio_api", "LM Studio (API)", "api", nil, nil, "openai", "http://localhost:1234/v1"),
    Preset.new("openai_compatible_api", "OpenAI-compatible server (API)", "api", nil, nil, "openai", "http://localhost:8080/v1")
  ].index_by(&:key).freeze

  # Spec 022, R1: a model name is passed to the tool as one argument, so it must never look like an option.
  MODEL_NAME = %r{\A[A-Za-z0-9._:/@][A-Za-z0-9._:/@-]{0,199}\z}
  MODEL_NAME_RULE = "may use letters, digits and . _ : / @ - only, and must not start with -"
  # Spec 022, G5: effort levels each tool accepts; only these are ever passed. Other presets take none.
  EFFORTS = { "claude_code" => %w[low medium high xhigh max], "codex" => %w[minimal low medium high xhigh max ultra] }.freeze
  CLAUDE_ALIASES = %w[opus sonnet haiku].freeze # spec 022, Q3: the CLI lists no models
  MAX_EXTRA_MODELS = 50

  def self.valid_model_name?(name) = name.nil? || name.match?(MODEL_NAME)

  has_many :agents, dependent: :restrict_with_error # spec 009, S4: in use → cannot be deleted

  normalizes :extra_models, with: ->(value) { value.to_s.lines.map(&:strip).reject(&:empty?).uniq.join("\n").presence }
  normalizes :effort, with: ->(value) { value.to_s.strip.presence }
  normalizes :name, :default_model, :notes, with: ->(value) { value.to_s.strip.presence }
  normalizes :base_url, with: ->(value) { value.to_s.strip.delete_suffix("/").presence }

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { case_sensitive: false }
  validates :preset, inclusion: { in: PRESETS.keys, message: "is not one of the presets" }
  validates :default_model, length: { maximum: 200 }
  validates :default_model, format: { with: MODEL_NAME, message: MODEL_NAME_RULE }, allow_nil: true
  validates :notes, length: { maximum: 2000 }
  validate :base_url_allowed
  validate :extra_models_allowed
  validate :effort_allowed

  before_validation :apply_preset_defaults

  scope :ordered, -> { order(:name) }

  def preset_definition = PRESETS[preset]
  def kind = preset_definition&.kind
  def cli? = kind == "cli"
  def api? = kind == "api"
  def label = preset_definition&.label || preset

  def check!
    result = ExecutorCheck.new(self).run
    update!(last_checked_at: Time.current, last_check_ok: result.ok, last_check_output: result.output)
    result
  end

  # Spec 022, G5: the effort levels this executor's tool takes (none for most presets).
  def efforts = EFFORTS.fetch(preset, [])

  def extra_model_names = extra_models.to_s.lines.map(&:strip).reject(&:empty?)

  # Spec 022, G1/G2: what the forms offer — the tool's list, the Claude aliases and the admin's names, each once.
  def model_choices
    listed = Array(models).filter_map { |m| m.is_a?(Hash) && self.class.valid_model_name?(m["name"].to_s.presence) && m["name"].present? ? m.slice("name", "efforts") : nil }
    listed = CLAUDE_ALIASES.map { |name| { "name" => name, "efforts" => [] } } + listed if preset == "claude_code"
    (listed + extra_model_names.map { |name| { "name" => name, "efforts" => [] } }).uniq { |m| m["name"] }
  end

  # G3, R5: a fresh list replaces the old one; a failure keeps the old list with a note.
  def refresh_models!
    result = ModelList.new(self).run
    if result.ok
      update!(models: result.models, models_listed_at: Time.current, models_note: result.note)
    else
      update!(models_note: models_listed_at ? "Out of date: #{result.note}" : result.note)
    end
    result
  end

  private

  def extra_models_allowed
    names = extra_model_names
    errors.add(:extra_models, "may list at most #{MAX_EXTRA_MODELS} names") if names.size > MAX_EXTRA_MODELS
    bad = names.reject { |name| name.match?(MODEL_NAME) }
    errors.add(:extra_models, "#{MODEL_NAME_RULE} (#{bad.first(3).join(", ")})") if bad.any?
  end

  def effort_allowed
    errors.add(:effort, "is not one this tool takes") if effort && !efforts.include?(effort)
  end

  def apply_preset_defaults
    if api?
      self.base_url ||= preset_definition.default_url
    else
      self.base_url = nil # CLI executors have no address
    end
  end

  def base_url_allowed
    return unless api?
    return errors.add(:base_url, "can't be blank") if base_url.blank?

    uri = URI.parse(base_url)
    errors.add(:base_url, "must start with http:// or https://") unless uri.is_a?(URI::HTTP) && uri.host.present?
    errors.add(:base_url, "must not contain a user name or password") if uri.userinfo
    errors.add(:base_url, "must not contain a query or fragment") if uri.query || uri.fragment
    errors.add(:base_url, "is too long") if base_url.length > 300
  rescue URI::InvalidURIError
    errors.add(:base_url, "is not a valid address")
  end
end
