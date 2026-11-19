require "securerandom"
require "yaml"
require "fileutils"

module Agentaro
  # Machine-local secrets (spec 002): secret_key_base and Active Record encryption keys.
  #
  # The repository is public, so secrets never live in it. On first boot they are generated into
  # storage/secrets.yml (ignored by git, mode 0600). Environment variables override the file.
  # Losing the file makes encrypted TOTP secrets unreadable — back it up together with storage/.
  module LocalSecrets
    KEYS = {
      "secret_key_base" => -> { SecureRandom.hex(64) },
      "active_record_encryption_primary_key" => -> { SecureRandom.alphanumeric(32) },
      "active_record_encryption_deterministic_key" => -> { SecureRandom.alphanumeric(32) },
      "active_record_encryption_key_derivation_salt" => -> { SecureRandom.alphanumeric(32) }
    }.freeze

    def self.load(path)
      stored = File.exist?(path) ? (YAML.safe_load_file(path) || {}) : {}
      missing = KEYS.keys - stored.keys
      unless missing.empty?
        missing.each { |key| stored[key] = KEYS.fetch(key).call }
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, stored.to_yaml)
        File.chmod(0o600, path)
      end
      KEYS.keys.to_h { |key| [ key, ENV.fetch(key.upcase, stored.fetch(key)) ] }
    end
  end
end
