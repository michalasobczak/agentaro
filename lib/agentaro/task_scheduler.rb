module Agentaro
  # Spec 010: starts task runs at their time. Lives in the server process: one thread looks for due
  # occurrences every INTERVAL seconds, worker threads run them one at a time each (spec 036: as many as R7 says).
  #
  # Due means: the task has an agent, the occurrence started at most GRACE ago (Q2: never run late) and
  # after the agent was assigned (R1). The unique index on scheduled runs makes this safe to repeat.
  #
  # Spec 036: workers no longer take run ids from a queue in turn. The saved runs are the queue: a worker claims the
  # oldest queued run that may start now — a step only while its agent has a free slot (R2), and only while no other
  # step works in the same working folder (R6, see claim_for) — and leaves the others queued. Claims happen one at a
  # time under a lock, against the runs that are running and the ones this process has just claimed, so two workers
  # never pass the same limit or take the same run. The pool grows with the highest agent limit (R7).
  module TaskScheduler
    INTERVAL = 30 # seconds
    GRACE = 120   # seconds; older occurrences are missed, not run
    PICK_WINDOW = 500 # queued runs looked at per claim, oldest first
    ORPHAN_GRACE = 5 * 60 # seconds after the run timeout an outlived executor is no longer waited for (R5)

    Claim = Data.define(:run_id, :agent_id, :folder)

    @signals = Thread::Queue.new # wake-ups only: something was queued or a slot was freed
    @workers = []
    @ticker = nil
    @target = 0
    @lock = Mutex.new   # start and pool size
    @claims = Mutex.new # one claim at a time
    @active = {}        # run id => Claim, from the claim until its run has finished
    @orphans = []       # runs left running by an executor that outlived the last stop (R5)

    class << self
      # workers: a fixed pool (tests); otherwise sized by the agents' limits (R7).
      def start(workers: nil)
        @lock.synchronize do
          return false if running?

          recover!
          @fixed = workers
          @ticker = Thread.new { tick_forever }.tap { |t| t.name = "agentaro-scheduler" }
          resize_locked
          Rails.logger.info("[runs] scheduler started with #{@target} workers")
        end
        wake
        true
      end

      def running? = !!(@ticker&.alive? || @workers.any?(&:alive?))

      # Manual runs ("Run now") and recovered runs; without a running scheduler they wait as queued.
      def enqueue(_run_id = nil) = wake

      # Spec 036: something may start now (a run was queued, a slot was freed, a limit was changed).
      def wake(rescale: false)
        return unless running?

        resize if rescale
        @signals << :wake
      end

      # R7: one agent at its highest limit, plus the workers for the director's work (config.x.run_workers).
      def worker_target
        return @fixed if @fixed

        base = Rails.application.config.x.run_workers
        limit = Rails.application.executor.wrap { Agent.highest_parallel_limit }
        base + limit.clamp(Agent::PARALLEL_RANGE)
      end

      # The steps this process is running now, by agent (for tests and logs).
      def claimed = @claims.synchronize { @active.values.dup }

      # Creates scheduled runs for due occurrences; returns them. Called by the ticker and by tests.
      def tick(now: Time.current)
        ManagementRunner.dispatch_due(now: now) # spec 011: new work items go to the director (spec 016: at once)
        StepChain.start_due(now: now)          # spec 016: epics whose start has come run their first step
        StepRetry.hand_over_due(now: now)      # spec 032: retries whose time has come
        StepReview.review_running_due(now: now) # spec 040, G4: the director looks at long-running steps
        RecurringOrder.run_due(now: now)       # spec 034: recurring orders whose time has come
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

      # After a restart: runs that were running were interrupted; queued ones stay queued and are claimed again (the
      # saved runs are the queue, R5). An executor process that outlived the restart keeps its slot until it has ended.
      def recover!
        Rails.application.executor.wrap do
          TaskRun.where(state: "running").find_each do |run|
            next if claimed_here?(run.id)
            next @orphans |= [ run.id ] if executor_alive?(run)

            interrupt!(run)
          end
        end
      end

      # R5: runs whose executor outlived the restart are freed once it has ended (checked by the ticker).
      def settle_orphans!
        @orphans = @orphans.select do |id|
          run = TaskRun.find_by(id: id, state: "running") or next false
          next true if executor_alive?(run)

          interrupt!(run)
          wake
          false
        end
      end

      # Claims the oldest run that may start now; nil when none may. Public for tests (the bar of S2).
      def claim_next
        @claims.synchronize do
          Rails.application.executor.wrap do
            ActiveRecord::Base.uncached do
              claim = nil
              TaskRun.where(state: "queued").where.not(id: @active.keys).order(:id).limit(PICK_WINDOW).each do |run|
                break if (claim = claim_for(run))
              end
              @active[claim.run_id] = claim if claim
              claim
            end
          end
        end
      end

      # The end of a claimed run: its slot is free for the next claim (R5).
      def release(claim)
        @claims.synchronize { @active.delete(claim.run_id) }
        wake
      end

      # Runs one claimed run to its end; the slot is released afterwards, whatever happened.
      def process(claim)
        # Owner fix: no query cache in runs — they last minutes and must see what other requests save (a newer
        # chat message, a cancelled epic); the executor would otherwise keep answering from its cache.
        Rails.application.executor.wrap do
          ActiveRecord::Base.uncached do
            run = TaskRun.find_by(id: claim.run_id, state: "queued")
            next unless run

            run.update!(agent_id: claim.agent_id) if run.step? && run.agent_id != claim.agent_id # R2: the task's agent now
            if run.purpose == "epic_step" then StepChain.new(run).perform! # spec 016
            elsif run.purpose == "step_review" then StepReviewer.new(run).perform! # spec 040
            elsif run.step? then TaskRunner.new(run).perform!
            else ManagementRunner.new(run).perform!
            end
          end
        end
      rescue StandardError => e
        Rails.logger.error("[runs] worker failed on run #{claim.run_id}: #{e.class}: #{e.message}")
      ensure
        release(claim)
      end

      private

      def claimed_here?(run_id) = @claims.synchronize { @active.key?(run_id) }

      def interrupt!(run)
        run.update!(state: "failed", error: "Interrupted: Agentaro stopped while this run was in progress.", finished_at: Time.current)
        if run.purpose == "epic_step"
          ProcessTracker.stop_saved(LiveLog.dir_for(run.id)) # spec 040, R8: what the step left running before the restart
          StepChain.after_run(run) # spec 040: the director decides what next
        end
        StepReviewer.interrupted(run) if run.purpose == "step_review"
      end

      # R5: the run's process group still exists. Only while the run could still be within its time limit: after that a
      # live group with this number is taken for another program (numbers are reused), never killed.
      def executor_alive?(run)
        return false unless run.pid && run.started_at
        limit = run.purpose == "epic_step" && run.epic_step ? run.epic_step.time_limit_seconds : Rails.application.config.x.run_timeout # spec 040, G2
        return false if run.started_at < Time.current - limit - ORPHAN_GRACE

        Process.kill(0, -run.pid)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end

      # Whether this queued run may start now, as a Claim; nil leaves it queued (called under @claims).
      def claim_for(run)
        return if StepRetry.waiting?(run) # spec 032: the tick hands it over when due
        return if run.purpose == "epic_step" && run.work_item&.paused? # spec 048, R1: a paused epic starts nothing
        return Claim.new(run.id, nil, nil) unless run.limited? # chat, planning, verification: their own rules (R1)

        agent_id = run.step? ? run.task&.agent_id : run.agent_id # a calendar run reads its task's agent at run time
        folder = working_folder(run)
        if agent_id && (limit = Agent.where(id: agent_id).pick(:max_parallel_tasks))
          return if slots_used(agent_id) >= limit # R2, R4: a lowered limit waits until fewer run
        end
        return if folder && folder_busy?(folder)

        Claim.new(run.id, agent_id, folder)
      end

      # R2: running in the database or claimed here and about to run, counted once.
      def slots_used(agent_id)
        ids = TaskRun.occupying(agent_id).pluck(:id)
        (ids | @active.values.select { |c| c.agent_id == agent_id }.map(&:run_id)).size
      end

      # R6 (owner's decision): an agent has no folder of its own; a step of a space with a working folder works in that
      # folder (spec 018), so only one step at a time works in one folder (resolved, so two spaces on the same folder or
      # a link to it share it). Steps of spaces with different folders run side by side.
      def working_folder(run)
        return unless run.purpose == "epic_step"

        dir = run.work_item&.space&.working_dir.presence or return
        File.realpath(dir)
      rescue SystemCallError
        File.expand_path(dir)
      end

      def folder_busy?(folder)
        return true if @active.values.any? { |c| c.folder == folder }

        TaskRun.where(state: "running", purpose: "epic_step").includes(work_item: :space).any? { |r| working_folder(r) == folder }
      end

      def resize
        @lock.synchronize { resize_locked }
      end

      # R7: more workers at once when the target grows; when it shrinks, idle workers leave after their current run.
      def resize_locked
        @target = worker_target
        @workers.select!(&:alive?)
        (@workers.size...@target).each do
          @workers << Thread.new { work }.tap { |t| t.name = "agentaro-run-#{@workers.size + 1}" }
        end
        (@workers.size - @target).times { @signals << :wake } if @workers.size > @target
      end

      def retire?
        @lock.synchronize do
          next false unless @workers.size > @target

          @workers.delete(Thread.current)
          true
        end
      end

      def tick_forever
        loop do
          begin
            queued = Rails.application.executor.wrap do
              tick
              settle_orphans! # spec 036, R5
              TaskRun.where(state: "queued").exists?
            end
            resize                         # spec 036, R7: limits changed elsewhere count too
            @signals << :wake if queued    # a queued run may have become startable (a retry's time)
            Rails.application.executor.wrap { RunTrace.run_if_due } # spec 030, G6: once a day
            Brain::Worker.kick # spec 031: extraction and the daily work, in their own thread
          rescue StandardError => e
            Rails.logger.error("[runs] scheduler tick failed: #{e.class}: #{e.message}")
          end
          sleep INTERVAL
        end
      end

      def work
        loop do
          break if retire?

          claim = claim_next
          unless claim
            @signals.pop # nothing may start: wait until something is queued or a slot is freed
            next
          end
          @signals << :wake # another idle worker may claim the next one meanwhile
          process(claim)
        rescue StandardError => e
          Rails.logger.error("[runs] worker failed: #{e.class}: #{e.message}")
          sleep 1
        end
      end
    end
  end
end
