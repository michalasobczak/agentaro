module Agentaro
  # Spec 010: starts task runs at their time. Lives in the server process: one thread looks for due
  # occurrences every INTERVAL seconds, worker threads (2, Q4) run them one at a time each.
  #
  # Due means: the task has an agent, the occurrence started at most GRACE ago (Q2: never run late) and
  # after the agent was assigned (R1). The unique index on scheduled runs makes this safe to repeat.
  module TaskScheduler
    INTERVAL = 30 # seconds
    GRACE = 120   # seconds; older occurrences are missed, not run

    @queue = Thread::Queue.new
    @threads = []
    @lock = Mutex.new

    class << self
      def start(workers: Rails.application.config.x.run_workers)
        @lock.synchronize do
          return false if running?

          recover!
          @threads = Array.new(workers) { |i| Thread.new { work } .tap { |t| t.name = "agentaro-run-#{i + 1}" } }
          @threads << Thread.new { tick_forever }.tap { |t| t.name = "agentaro-scheduler" }
          Rails.logger.info("[runs] scheduler started with #{workers} workers")
          true
        end
      end

      def running? = @threads.any?(&:alive?)

      # Manual runs ("Run now") and recovered runs; without a running scheduler they wait as queued.
      def enqueue(run_id)
        @queue << run_id if running?
      end

      # Creates scheduled runs for due occurrences; returns them. Called by the ticker and by tests.
      def tick(now: Time.current)
        due(now).filter_map do |occurrence|
          run = TaskRun.create!(task: occurrence.task, occurrence_start: occurrence.original_start, trigger: "scheduled")
          enqueue(run.id)
          run
        rescue ActiveRecord::RecordNotUnique
          nil # already scheduled (restart or another process)
        end
      end

      def due(now)
        from = now - GRACE
        reach = Task::SERIES_LIMIT + Task::MAX_DURATION
        Task.where.not(agent_id: nil).where(starts_at: (from - reach)..now).includes(:exceptions).flat_map do |task|
          assigned = task.agent_assigned_at or next []
          task.occurrence_starts.select { |start| start > from && start <= now && start >= assigned }
              .map { |start| task.occurrence_at(start) }
        end.reject { |o| TaskRun.exists?(task_id: o.task.id, occurrence_start: o.original_start, trigger: "scheduled") }
      end

      # After a restart: runs that were running were interrupted; queued ones are picked up again.
      def recover!
        Rails.application.executor.wrap do
          TaskRun.where(state: "running").find_each do |run|
            run.update!(state: "failed", error: "Interrupted: Agentaro stopped while this run was in progress.", finished_at: Time.current)
          end
          TaskRun.where(state: "queued").order(:id).pluck(:id).each { |id| @queue << id }
        end
      end

      private

      def tick_forever
        loop do
          begin
            Rails.application.executor.wrap { tick }
          rescue StandardError => e
            Rails.logger.error("[runs] scheduler tick failed: #{e.class}: #{e.message}")
          end
          sleep INTERVAL
        end
      end

      def work
        loop do
          id = @queue.pop
          Rails.application.executor.wrap do
            run = TaskRun.find_by(id: id, state: "queued")
            TaskRunner.new(run).perform! if run
          end
        rescue StandardError => e
          Rails.logger.error("[runs] worker failed on run #{id}: #{e.class}: #{e.message}")
        end
      end
    end
  end
end
