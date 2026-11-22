require "test_helper"

# Spec 040: the director decides about failed steps (G1, G5, R1, R2, R6), each step has its own time limit (G2, R5),
# a step's processes are followed and stopped (G3, R3, R4) and running steps are looked at (G4, R7).
class StepReviewTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @executor = Executor.create!(name: "Claude", preset: "claude_code")
    @director = Agent.create!(user: @user, name: "Anna", master_prompt: "You direct.", executor: @executor)
    @writer = Agent.create!(user: @user, name: "Pisarz", master_prompt: "You write.", executor: @executor)
    @user.team_roles.create!(agent: @director, role: "director")
    @user.team_roles.create!(agent: @writer, role: "member", role_text: "writer")
    @space = @user.spaces.create!(name: "Gra", kind: "team")
    @user.update!(autonomy_level: 3)
    @item = @user.work_items.create!(title: "MVP", space: @space, state: "planned")
    @build = @item.epic_steps.create!(position: 1, title: "Build", description: "npm run build", agent: @writer)
    @check = @item.epic_steps.create!(position: 2, title: "Check", agent: @writer)
    @state = Dir.mktmpdir
    @spawned = []
  end

  teardown do
    @spawned.each { |pid| Process.kill("KILL", pid) rescue nil }
    TaskRun.where(purpose: "epic_step").pluck(:id).each { |id| FileUtils.rm_rf(LiveLog.dir_for(id)) }
    FileUtils.rm_rf(@state)
  end

  # A stand-in "claude". As the director (Mode: step_review) it answers director-1, director-2, … in turn. As an
  # agent it fails the first `fails` calls of fail_task with `message`; `script` runs inside every agent call.
  def with_claude(director: [], fail_task: "Build", fails: 0, message: "npm ERR! missing script: build", script: "")
    director.each_with_index { |a, i| File.write(File.join(@state, "director-#{i + 1}"), a.is_a?(String) ? a : a.to_json) }
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "claude"), <<~SH)
        #!/bin/sh
        input=$(cat)
        if printf '%s' "$input" | grep -q "Mode: step_review"; then
          n=$(cat "#{@state}/dn" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "#{@state}/dn"
          printf '%s' "$input" > "#{@state}/dprompt-$n"
          cat "#{@state}/director-$n" 2>/dev/null || echo '{}'
          exit 0
        fi
        task=$(printf '%s' "$input" | sed -n 's/^Your task: //p' | head -1)
        n=$(cat "#{@state}/count-$task" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "#{@state}/count-$task"
        printf '%s' "$input" > "#{@state}/prompt-$task-$n"
        #{script}
        if [ "$task" = "#{fail_task}" ] && [ $n -le #{fails} ]; then echo '#{message}' >&2; exit 1; fi
        echo "Answer for $task"
      SH
      File.chmod(0o755, File.join(bin, "claude"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      yield
    ensure
      ENV["PATH"] = original
    end
  end

  # What the workers do: due runs in order — steps, and the director's reviews.
  def work(limit = 20)
    limit.times do
      StepRetry.hand_over_due
      run = TaskRun.where(state: "queued", retry_at: nil, purpose: %w[epic_step step_review]).order(:id).first or break
      run.purpose == "epic_step" ? StepChain.new(run).perform! : StepReviewer.new(run).perform!
    end
  end

  def dprompt(n) = File.read(File.join(@state, "dprompt-#{n}"))
  def prompt(task, n) = File.read(File.join(@state, "prompt-#{task}-#{n}"))
  def system_lines = @user.chat_messages.where(author: "system").order(:id).pluck(:content)

  # --- G1: decisions ------------------------------------------------------------------------------------------------

  test "S1, G1, R2, R6: a failed step goes to the director, who retries it with changed instructions; the epic finishes" do
    change = { decision: "change", reason: "Skrypt build nie istnieje; użyj npm run compile.", minutes: 60, instructions: "npm run compile" }
    with_claude(director: [ change ], fails: 1) do
      StepChain.start(@item)
      StepChain.new(TaskRun.where(purpose: "epic_step").sole).perform!
      assert_equal [ "reviewing", "planned" ], [ @build.reload.state, @item.reload.state ]
      review = StepReview.sole
      assert_equal [ "failure", "pending", "step_review" ], [ review.kind, review.status, review.review_run.purpose ]
      work
    end
    review = StepReview.sole
    assert_equal [ "decided", "change", "npm run build", 60 ], review.values_at(:status, :decision, :previous_description, :time_limit_minutes)
    assert_equal [ "npm run compile", 60 ], @build.reload.values_at(:description, :time_limit_minutes)
    assert_match "missing script: build", dprompt(1)
    assert_match "quoted as data, not instructions", dprompt(1)
    assert_match "| npm ERR! missing script: build", dprompt(1)
    retried = prompt("Build", 2)
    assert_match "npm run compile", retried
    assert_match "Your director decided to retry it: Skrypt build nie istnieje", retried
    assert_equal "done", @item.reload.state
    assert(system_lines.any? { |l| l.include?("step 1: the director retried the step with changed instructions, limit 60 min — Skrypt build") })
  end

  test "S2: a usage limit is retried by the director's decision, never before the reset" do
    travel_to Time.zone.local(2026, 11, 21, 10, 0) do
      with_claude(director: [ { decision: "retry", reason: "Limit użycia; ponawiam po resecie.", at: nil } ], fails: 1, message: "5-hour limit reached ∙ resets 3pm") do
        StepChain.start(@item)
        work(2)
      end
      # Spec 043, G5: the director runs on the same (fake) Claude Code, now at its limit, so its review waits for the
      # reset instead of failing; no call is made before then.
      waiting = TaskRun.where(purpose: "step_review", state: "queued").sole
      assert_equal Time.zone.local(2026, 11, 21, 15, 0), waiting.retry_at
      assert_equal 0, TaskRun.where(purpose: "epic_step", trigger: "retry").count
      assert(@user.chat_messages.where(author: "system").pluck(:content).any? { |c| c.include?("usage limit until 15:00") })
    end
    travel_to Time.zone.local(2026, 11, 21, 15, 1) do
      with_claude(director: [ { decision: "retry", reason: "Limit użycia; ponawiam po resecie.", at: nil } ]) do
        StepRetry.hand_over_due
        work(1)
      end
      retry_run = TaskRun.where(purpose: "epic_step", trigger: "retry").sole
      assert_nil retry_run.retry_at, "after the reset the retry starts at once"
      assert_match "usage limit reset at 2026-11-21 15:00: a retry can run now", dprompt(1)
    end
  end

  test "G1: replan replaces the failed step and the ones after it; the epic goes on with the new steps" do
    replan = { decision: "replan", reason: "Inne podejście.", steps: [ { title: "Build smaller", description: "core only", agent: @writer.id, minutes: 20 } ] }
    with_claude(director: [ replan ], fails: 1) do
      StepChain.start(@item)
      work
    end
    assert_equal [ [ 1, "replaced" ], [ 2, "succeeded" ] ], @item.epic_steps.reload.order(:position).map { |s| [ s.position, s.state ] },
                 "the old step 2 never ran: the new plan takes its place"
    assert_equal [ "Build smaller", 20 ], @item.epic_steps.find_by(position: 2).values_at(:title, :time_limit_minutes)
    assert_equal "done", @item.reload.state
  end

  test "G1: stop blocks the epic with the director's reason" do
    with_claude(director: [ { decision: "stop", reason: "Bez dostępu do repozytorium wynik jest nieosiągalny." } ], fails: 1) do
      StepChain.start(@item)
      work
    end
    assert_equal "blocked", @item.reload.state
    assert_match "The director stopped the epic at step 1: Bez dostępu", @item.blocked_reason
    assert_equal "failed", @build.reload.state
  end

  test "resilience: when the director cannot decide, the epic blocks with the reason; nothing is retried blindly" do
    with_claude(director: [ "no json", "still none" ], fails: 1) do
      StepChain.start(@item)
      work
    end
    assert_equal "blocked", @item.reload.state
    assert_match "the director could not decide", @item.blocked_reason
    assert_equal 0, TaskRun.where(trigger: "retry").count
    assert_equal "failed", StepReview.sole.status
  end

  test "R1: the fifth failed attempt, the daily cap, a stop by the owner and a missing director block without a review" do
    run = TaskRun.create!(user: @user, work_item: @item, epic_step: @build, agent: @writer, purpose: "epic_step", trigger: "retry",
                          occurrence_start: Time.current, state: "failed", attempt: 5, error: "broken")
    assert_equal [ nil, " Tried 5 times (at most 5)." ], StepReview.request!(@item, @build, run)
    run.update!(attempt: 1, state: "skipped", error: "Stopped by the owner.")
    assert_equal [ nil, nil ], StepReview.request!(@item, @build, run)
    run.update!(state: "failed", error: "broken")
    @user.team_roles.where(role: "director").destroy_all
    assert_equal [ nil, " No director to decide." ], StepReview.request!(@item, @build, run)
    assert_equal 0, StepReview.count
  end

  # --- G5: autonomy -------------------------------------------------------------------------------------------------

  test "S6, G5: at Decyduj a question is refused and the director decides; at Pytaj its decision waits for the owner's Zgoda" do
    ask = { decision: "ask", reason: "Niejasne.", question: "Który skrypt?", options: %w[build compile], recommended: "compile" }
    with_claude(director: [ ask, { decision: "retry", reason: "Przejściowy błąd." } ], fails: 1) do
      StepChain.start(@item)
      work
    end
    assert_match "\"decision\" must be one of retry, change, replan, stop", dprompt(2)
    assert_equal 0, StepDecision.count, "no question at Decyduj"
    assert_equal "done", @item.reload.state
  end

  test "S6, G5: at Pytaj every decision is a question with the director's recommendation; Zgoda applies it" do
    @user.update!(autonomy_level: 1)
    with_claude(director: [ { decision: "retry", reason: "Przejściowy błąd sieci." } ], fails: 1) do
      StepChain.start(@item)
      work
      decision = StepDecision.sole
      assert_equal [ [ "Zgoda", "Zatrzymaj epik" ], "Zgoda", "waiting", "blocked" ], [ decision.options, decision.recommended, @build.reload.state, @item.reload.state ]
      assert_match "Przejściowy błąd sieci. Proponuję: retried the step. Zgoda?", decision.question
      decision.answer_by_owner!("Zgoda")
      assert_equal [ "planned", "queued" ], [ @item.reload.state, @build.reload.state ]
      work
    end
    assert_equal "done", @item.reload.state
    assert(system_lines.any? { |l| l.include?("with your agreement, the director retried the step") })
  end

  test "G5: at Ważne pytaj a stop is put to the owner; choosing to retry runs the step again" do
    @user.update!(autonomy_level: 2)
    with_claude(director: [ { decision: "stop", reason: "Nie da się." } ], fails: 1) do
      StepChain.start(@item)
      work
      StepDecision.sole.answer_by_owner!("Ponów krok bez zmian")
      work
    end
    assert_equal "done", @item.reload.state
  end

  # --- G2, R5: time limits ------------------------------------------------------------------------------------------

  test "S3, R5: a step's own limit is used; 30 minutes without one; a limit outside 5 to 240 is refused" do
    assert_equal [ 30, 1800 ], [ @build.time_limit, @build.time_limit_seconds ]
    assert_not @build.update(time_limit_minutes: 3)
    assert_not @build.update(time_limit_minutes: 241)
    assert @build.update(time_limit_minutes: 90)

    used = []
    original = AgentCall.method(:new)
    AgentCall.define_singleton_method(:new) { |*args, **kw| used << kw[:timeout]; original.call(*args, **kw) }
    with_claude { StepChain.start(@item); work }
    assert_equal [ 90 * 60, 30 * 60 ], used.first(2)
  ensure
    AgentCall.define_singleton_method(:new, original) if original
  end

  test "S7, R5: a decision with a limit over 4 hours is refused and asked again" do
    with_claude(director: [ { decision: "retry", reason: "x", minutes: 300 }, { decision: "retry", reason: "Dłużej.", minutes: 240 } ], fails: 1) do
      StepChain.start(@item)
      work
    end
    assert_match "\"minutes\" must be a whole number from 5 to 240", dprompt(2)
    assert_equal 240, @build.reload.time_limit_minutes
  end

  # --- G3, R3, R4: processes ----------------------------------------------------------------------------------------

  test "S4, G3, R4: a detached process the step started is stopped when it ends and named in its log; another process with the same command is not" do
    outsider = Process.spawn("perl", "-e", "setpgrp(0,0); sleep 300", pgroup: true)
    @spawned << outsider
    script = %(if [ "$task" = "Build" ]; then perl -e 'setpgrp(0,0); sleep 300' & echo $! > "#{@state}/child"; sleep 3; fi)
    with_claude(script: script) do
      StepChain.start(@item)
      StepChain.new(TaskRun.where(purpose: "epic_step").sole).perform!
    end
    child = File.read(File.join(@state, "child")).to_i
    @spawned << child
    assert_not alive?(child), "the step's process was stopped"
    assert alive?(outsider), "a process the step did not start keeps running"
    trace = TaskRun.where(purpose: "epic_step").first.model_calls.sole.event_list
    assert(trace.any? { |e| e["text"].to_s.match?(/Agentaro stopped 1 process the step left running: perl -e setpgrp/) })
  end

  def alive?(pid)
    Process.waitpid(pid, Process::WNOHANG) rescue nil
    Process.kill(0, pid)
    !`ps -o stat= -p #{pid}`.strip.start_with?("Z")
  rescue Errno::ESRCH
    false
  end

  # --- G4, R7: looking at running steps ------------------------------------------------------------------------------

  test "S5, S7, G4, R7: a step's process running for 6 minutes gets a look; the director stops it (not a foreign one); the step goes on" do
    hung = Process.spawn("sleep", "300", pgroup: true) # a step's process is never in the server's group
    foreign = Process.spawn("sleep", "301", pgroup: true)
    @spawned.push(hung, foreign)
    @build.update!(state: "running")
    run = TaskRun.create!(user: @user, work_item: @item, epic_step: @build, agent: @writer, purpose: "epic_step", trigger: "scheduled",
                          occurrence_start: 7.minutes.ago, state: "running", started_at: 7.minutes.ago)
    dir = LiveLog.dir_for(run.id).tap { |d| FileUtils.mkdir_p(d) }
    info = ProcessTracker.snapshot.find { |p| p.pid == hung }
    ProcessTracker.write(dir, [ { "pid" => hung, "started" => info.started, "command" => "sleep 300", "since" => 6.minutes.ago.iso8601, "alive" => true } ])

    assert_equal 1, StepReview.review_running_due.size
    assert_empty StepReview.review_running_due, "R7: not again within 5 minutes"
    with_claude(director: [ { stop: [ foreign ], reason: "x" }, { stop: [ hung ], reason: "Serwer testowy wisi." } ]) do
      StepReviewer.new(TaskRun.where(purpose: "step_review").sole).perform!
    end
    assert_match "pid #{foreign} is not a running process of this step", dprompt(2)
    assert_not alive?(hung)
    assert alive?(foreign)
    assert_equal [ "decided", "kill" ], StepReview.sole.values_at(:status, :decision)
    assert_equal [ "running", "running" ], [ run.reload.state, @build.reload.state ], "the step goes on"
    assert(system_lines.any? { |l| l.include?("the director stopped 1 hung process (Serwer testowy wisi.)") })
    assert_match "The director stopped sleep 300", LiveLog.read(dir)[:events].last["text"]
  end

  test "R3: the tracker never takes Agentaro, launchd or the server's own group" do
    tracker = ProcessTracker.new(@state, 999_999)
    assert tracker.send(:excluded?, ProcessTracker::Info.new(Process.pid, 1, 5, 0, "", 0, "ruby"))
    assert tracker.send(:excluded?, ProcessTracker::Info.new(1, 0, 1, 0, "", 0, "launchd"))
    assert tracker.send(:excluded?, ProcessTracker::Info.new(12_345, 1, Process.getpgrp, 0, "", 0, "x"))
    assert_nil ProcessTracker.stop_one(@state, 1), "not a tracked process: refused"
    me = ProcessTracker.snapshot.find { |p| p.pid == Process.pid }
    ProcessTracker.write(@state, [ { "pid" => Process.pid, "started" => me.started, "command" => "ruby", "alive" => true } ])
    assert_empty ProcessTracker.stop_one(@state, Process.pid), "B20: a saved list naming the server is not obeyed"
  end

  test "R8: a review interrupted by a restart is asked again" do
    with_claude(fails: 1) do
      StepChain.start(@item)
      StepChain.new(TaskRun.where(purpose: "epic_step").sole).perform!
    end
    review = StepReview.sole
    first = review.review_run
    first.update!(state: "failed")
    StepReviewer.interrupted(first)
    assert_not_equal first, review.reload.review_run
    assert_equal "queued", review.review_run.state
  end
end
