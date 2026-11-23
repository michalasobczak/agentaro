require "yaml"

# Spec 052, G1, R1: a space's `agentaro.yml` — four optional keys, each one command line (or an address). It is data:
# read safely, only these keys, limited in length; a broken file runs nothing and says why.
module Ci
  class Config
    FILE = "agentaro.yml"
    KEYS = %w[build test serve url].freeze
    MAX_VALUE = 1000
    MAX_FILE = 16 * 1024

    Invalid = Class.new(StandardError)

    attr_reader :build, :test, :serve, :url

    # The config of a folder, nil when it has no file; raises Invalid with the reason when the file is wrong.
    def self.for(dir)
      return unless dir.present?

      path = File.join(dir, FILE)
      return unless File.file?(path)
      raise Invalid, "#{FILE} is larger than #{MAX_FILE / 1024} KB" if File.size(path) > MAX_FILE

      data = YAML.safe_load(File.read(path), permitted_classes: [], aliases: false)
      raise Invalid, "#{FILE} must be a list of keys (build, test, serve, url)" unless data.is_a?(Hash)

      unknown = data.keys.map(&:to_s) - KEYS
      raise Invalid, "#{FILE}: unknown key#{"s" if unknown.size > 1} #{unknown.join(", ")} (only #{KEYS.join(", ")})" if unknown.any?

      new(data.transform_keys(&:to_s))
    rescue Psych::Exception => e
      raise Invalid, "#{FILE} is not valid YAML: #{e.message.truncate(200)}"
    end

    def initialize(data)
      KEYS.each do |key|
        value = data[key]
        next if value.nil?
        raise Invalid, "#{FILE}: #{key} must be one line of text" unless value.is_a?(String) && !value.include?("\n")
        raise Invalid, "#{FILE}: #{key} is longer than #{MAX_VALUE} characters" if value.length > MAX_VALUE

        instance_variable_set(:"@#{key}", value.strip.presence)
      end
      raise Invalid, "#{FILE}: url must start with http:// or https://" if @url && !@url.match?(%r{\Ahttps?://[^\s]+\z})
      # B20: the address is checked every 10 seconds and shown as a link; the file is the agents' to change, so it may
      # only name this computer.
      raise Invalid, "#{FILE}: url must be on this computer (localhost, 127.0.0.1 or [::1])" if @url && !local_url?(@url)
    end

    def ci? = build.present? || test.present?

    LOCAL_HOSTS = %w[localhost 127.0.0.1 ::1].freeze

    def local_url?(url)
      uri = URI.parse(url)
      LOCAL_HOSTS.include?(uri.host.to_s.delete_prefix("[").delete_suffix("]").downcase) && uri.userinfo.nil?
    rescue URI::InvalidURIError
      false
    end
  end
end
