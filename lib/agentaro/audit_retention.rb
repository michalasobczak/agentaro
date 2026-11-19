module Agentaro
  # Spec 005, F3: enforces the 3-month retention of the audit log and data changelog without manual
  # action. The running app checks at most once per INTERVAL (and right after it starts) and prunes in
  # a background thread, so no request waits for it. Failures are logged and retried next time.
  module AuditRetention
    INTERVAL = 24 * 60 * 60 # seconds (loaded before ActiveSupport core extensions)

    @lock = Mutex.new
    @last_run = nil

    class << self
      # Returns true when a prune was started.
      def run_if_due(now: Time.current, async: true)
        @lock.synchronize do
          return false if @last_run && @last_run > now - INTERVAL

          @last_run = now
        end
        job = -> { Rails.application.executor.wrap { prune! } }
        async ? Thread.new(&job) : job.call
        true
      end

      # Removes rows older than the retention period from both chains; returns the number removed.
      def prune!
        SignInThrottle.stale.find_each(&:destroy) # old failed-sign-in counters (spec 005, F4)
        [ AuditEvent, DataChange ].sum { |model| model.prune!(before: model::RETENTION.ago) }
      rescue StandardError => e
        Rails.logger.error("[audit] retention prune failed: #{e.class}: #{e.message}")
        0
      end

      def reset!
        @lock.synchronize { @last_run = nil }
      end
    end
  end
end
