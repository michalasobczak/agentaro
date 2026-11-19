# Spec 008: an AI tool Agentaro can use — a CLI on the host (logged in there, e.g. a subscription) or a
# local HTTP API that needs no token (Q2).
#
# What runs is decided only by PRESETS in code (Q3): the web chooses a preset, never a program,
# arguments or protocol.
class Executor < ApplicationRecord
  Preset = Data.define(:key, :label, :kind, :program, :version_args, :protocol, :default_url) do
    def cli? = kind == "cli"
    def api? = kind == "api"
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

  normalizes :name, :default_model, :notes, with: ->(value) { value.to_s.strip.presence }
  normalizes :base_url, with: ->(value) { value.to_s.strip.delete_suffix("/").presence }

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { case_sensitive: false }
  validates :preset, inclusion: { in: PRESETS.keys, message: "is not one of the presets" }
  validates :default_model, length: { maximum: 200 }
  validates :notes, length: { maximum: 2000 }
  validate :base_url_allowed

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

  private

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
