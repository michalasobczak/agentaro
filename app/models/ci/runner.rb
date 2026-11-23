# Spec 052, G2/G3/G6: one CI run of a space — build, then test, each in the sandbox with a 15-minute limit. The space
# keeps the result and the end of the log; a good build restarts a wanted server (G4).
module Ci
  class Runner
    def initialize(run) = @run = run

    def perform!
      space = @run.space or return finish("skipped", "The space is gone.")
      @run.update!(state: "running", started_at: Time.current)
      return finish_space(space, "error", "sandbox-exec is not on this computer.") unless Sandbox.available?

      config = begin
        Ci.config_for(space)
      rescue Config::Invalid => e
        return finish_space(space, "error", e.message)
      end
      return finish_space(space, "error", "The space has no #{Config::FILE} with build or test.") unless config&.ci?

      space.update!(ci_state: "running")
      log = +""
      state = "ok"
      [ [ "build", config.build ], [ "test", config.test ] ].each do |name, line|
        next unless line

        log << "$ #{name}: #{line}\n"
        result = HostProcess.run(Sandbox::PROGRAM, Sandbox.command(space, line), chdir: space.working_dir, timeout: STEP_TIMEOUT,
                                 max_output: MAX_OUTPUT, on_spawn: ->(pid) { RunControl.started(@run.id, pid) })
        RunControl.finished(@run.id)
        log << result.stdout.to_s << result.stderr.to_s
        log << "\n#{name} ended: #{result.ending}\n"
        next if result.success?

        state = "failed_#{name}"
        break
      end
      space.update!(ci_fingerprint: Ci.fingerprint(space.working_dir, space: space))
      finish_space(space, state, log)
      Server.restart!(space) if state == "ok" && space.server_wanted # G4: a good build restarts the server
      @run
    end

    private

    def finish_space(space, state, log)
      tail = RunTrace.redact(ExecutorCheck.clean_text(log)).first.lines.last(LOG_LINES).join
      space.update!(ci_state: state, ci_finished_at: Time.current, ci_log: tail)
      finish(state == "ok" ? "succeeded" : "failed", state == "ok" ? nil : "CI #{state.tr("_", " ")}", tail)
      say(space, state) if @run.trigger == "scheduled" && @run.user
    end

    def finish(state, error, output = nil)
      TaskRunner.finish!(@run, AgentCall::Outcome.new(state, output, error, nil))
      @run
    end

    # G3: the result of an automatic run, as one line in the chat (manual runs are seen where they were started).
    def say(space, state)
      text = state == "ok" ? "CI of \"#{space.name}\": build and tests passed." : "CI of \"#{space.name}\": #{state.tr("_", " ")}. The end of its log is on the space's page."
      ChatMessage.create!(user: @run.user, author: "system", content: text, task_run: @run)
    end
  end
end
