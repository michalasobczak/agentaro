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
    # config.time_zone = "Central Time (US & Canada)"
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

    # Command-line sessions are recorded as "cli:<user>" in the data changelog (spec 004).
    console { Current.actor = "cli:#{ENV.fetch("USER", "unknown")}" }
  end
end
