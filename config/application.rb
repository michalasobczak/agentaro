require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
# require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Boot-time code that is not reloaded (not autoloaded, see autoload_lib below).
require_relative "../lib/agentaro/local_secrets"
require_relative "../lib/agentaro/audit_middleware"
require_relative "../lib/agentaro/audit_retention"
require_relative "../lib/agentaro/task_scheduler"

module Agentaro
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks agentaro])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # Times are stored in UTC and shown in Europe/Warsaw for everyone (spec 007, Q8).
    config.time_zone = "Europe/Warsaw"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    # Machine-local secrets (spec 002) — generated into storage/secrets.yml, never committed.
    secrets = Agentaro::LocalSecrets.load(File.expand_path("../storage/secrets.yml", __dir__))
    config.secret_key_base = secrets.fetch("secret_key_base")
    config.active_record.encryption.primary_key = secrets.fetch("active_record_encryption_primary_key")
    config.active_record.encryption.deterministic_key = secrets.fetch("active_record_encryption_deterministic_key")
    config.active_record.encryption.key_derivation_salt = secrets.fetch("active_record_encryption_key_derivation_salt")

    # Behind a TLS-terminating proxy such as `tailscale serve` (spec 005, F1): Rails sees plain HTTP
    # from the proxy, so treat every request as HTTPS — Secure cookies and HSTS.
    if ENV["AGENTARO_HTTPS_PROXY"] == "1"
      config.assume_ssl = true
      config.force_ssl = true
    end

    # Hostnames the app answers to, comma-separated, e.g. "<host>.<tailnet>.ts.net" (spec 005, F2).
    # Kept out of the repository; the health check stays reachable on localhost.
    config.hosts.concat(ENV.fetch("AGENTARO_HOSTS", "").split(",").map(&:strip).reject(&:empty?))
    config.host_authorization = { exclude: ->(request) { request.path == "/up" } }

    # HTTP audit log (spec 003): first middleware, so every request is recorded — including static
    # files and requests rejected by host authorization.
    config.middleware.insert_before 0, Agentaro::AuditMiddleware

    # Audit retention is enforced automatically (spec 005, F3); tests call it explicitly instead.
    config.x.audit_auto_prune = true

    # Running tasks on agents (spec 010): a scheduler thread in the server process, each run in its own folder under
    # var/runs (outside storage/, which agents may not read). Spec 036, R7: the workers are the highest agent limit
    # (Agent::PARALLEL_RANGE, default 6) plus run_workers for the director's chat, planning and verification.
    config.x.task_scheduler = true
    config.x.run_workers = 2
    config.x.run_timeout = 30 * 60 # seconds; owner fix (2026-11-20): was 15 minutes, too short for research steps
    config.x.runs_dir = File.expand_path("../var/runs/#{Rails.env}", __dir__) # one folder per environment
    # Spec 018: the Docker socket agents may use in spaces with a working folder (Colima, else Docker Desktop).
    config.x.docker_socket = ENV.fetch("AGENTARO_DOCKER_SOCKET") do
      [ "~/.colima/default/docker.sock", "~/.docker/run/docker.sock" ].map { |p| File.expand_path(p) }.find { |p| File.exist?(p) }
    end
    # Spec 017: local voice tools (outside the repository, in storage/voice); paths can be changed in settings.
    voice_dir = File.expand_path("../storage/voice", __dir__)
    config.x.voice = {
      whisper_bin: ENV.fetch("AGENTARO_WHISPER_BIN", "/opt/homebrew/bin/whisper-cli"),
      whisper_model: ENV.fetch("AGENTARO_WHISPER_MODEL", File.join(voice_dir, "ggml-large-v3-turbo-q5_0.bin")),
      piper_bin: ENV.fetch("AGENTARO_PIPER_BIN", File.join(voice_dir, "piper-venv/bin/piper")),
      piper_voice: ENV.fetch("AGENTARO_PIPER_VOICE", File.join(voice_dir, "pl_PL-gosia-medium.onnx")),           # Polish
      piper_voice_en: ENV.fetch("AGENTARO_PIPER_VOICE_EN", File.join(voice_dir, "en_US-lessac-medium.onnx")),  # English (optional)
      # Spec 019: the verifier's own voices (optional; the main voice of the language when missing)
      piper_voice_verifier: ENV.fetch("AGENTARO_PIPER_VOICE_VERIFIER", File.join(voice_dir, "pl_PL-darkman-medium.onnx")),
      piper_voice_verifier_en: ENV.fetch("AGENTARO_PIPER_VOICE_VERIFIER_EN", File.join(voice_dir, "en_US-ryan-medium.onnx"))
    }

    # Command-line sessions are recorded as "cli:<user>" in the data changelog (spec 004).
    console { Current.actor = "cli:#{ENV.fetch("USER", "unknown")}" }
  end
end
