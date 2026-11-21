require "test_helper"

# Spec 036: one agent runs up to its limit of steps at the same time, in all spaces (S1–S6, R1–R7).
class ParallelTasksTest < ActiveSupport::TestCase
  Scheduler = Agentaro::TaskScheduler

  setup do
    @user = create_user
    @user.update!(auto_retry: false)
    @executor = Executor.create!(name: "Claude", preset: "claude_code")
    @agent = Agent.create!(user: @user, name: "Pisarz", master_prompt: "You write.", executor: @executor)
    @spaces = [ @user.spaces.create!(name: "Alpha", goal: "A"), @user.spaces.create!(name: "Beta", goal: "B") ]
    @dirs = Dir.mktmpdir
  end

  teardown do
    Scheduler.claimed.each { |claim| Scheduler.release(claim) }
    FileUtils.rm_rf(@dirs)
  end

  # An epic with one step of the agent, queued (StepChain.start). Each epic gets a space of its own unless one is
  # given: spec 037 runs the epics of one space one after another.
  def queued_step(title, space: nil, agent: @agent)
    space ||= @user.spaces.create!(name: "Space for #{title}", goal: "G")
    item = @user.work_items.create!(title: title, state: "planned", space: space)
    item.epic_steps.create!(position: 1, title: title, agent: agent)
    StepChain.start(item)
  end

  # A stand-in "claude": notes that it started, then waits until the test lets it go (a barrier).
  def with_waiting_agent
    bin = File.join(@dirs, "bin")
    FileUtils.mkdir_p(bin)
    File.write(File.join(bin, "claude"), <<~SH)
      #!/bin/sh
      input=$(cat)
      task=$(printf '%s' "$input" | sed -n 's/^Your task: //p' | head -1)
      pwd -P > "#{@dirs}/pwd-$task"
      touch "#{@dirs}/started-$task"
      i=0
      while [ ! -f "#{@dirs}/go-$task" ] && [ $i -lt 400 ]; do sleep 0.05; i=$((i+1)); done
      echo "same name $task" > shared.txt
      case "$task" in Fail*) echo "boom in $task" >&2; exit 1;; esac
      echo "Answer for $task"
    SH
    File.chmod(0o755, File.join(bin, "claude"))
    original = ENV["PATH"]
    ENV["PATH"] = "#{bin}:#{original}"
    yield
  ensure
    ENV["PATH"] = original
  end

  def started = Dir.glob(File.join(@dirs, "started-*")).map { |f| File.basename(f).delete_prefix("started-") }.sort
  def go(task) = FileUtils.touch(File.join(@dirs, "go-#{task}"))
  def pwd_of(task) = File.read(File.join(@dirs, "pwd-#{task}")).strip

  # n workers as the scheduler runs them: each claims a run and runs it to its end, or ends when none may start.
  def workers(count)
    count.times.map do
      Thread.new do
        claim = Scheduler.claim_next
        Scheduler.process(claim) if claim
      end
    end
  end

  def folder_space(name)
    dir = File.join(@dirs, "folder-#{name}").tap { |d| FileUtils.mkdir_p(d) }
    @user.spaces.create!(name: "Space #{name}", goal: "G", working_dir: dir)
  end

  def wait_for(seconds = 10)
    deadline = Time.current + seconds
    sleep 0.05 until yield || Time.current > deadline
    assert yield, "timed out waiting"
  end

  test "S1: the limit is 6 unless set, whole numbers 1 to 10, a refused value keeps the old one" do
    assert_equal 6, @agent.max_parallel_tasks
    assert_equal 6, Agent::PARALLEL_DEFAULT
    @agent.update!(max_parallel_tasks: 10)
    [ 0, 11, "1.5", "abc", nil ].each do |value|
      assert_not @agent.update(max_parallel_tasks: value), value.inspect
      assert_equal 10, @agent.reload.max_parallel_tasks
    end
    assert @agent.update(max_parallel_tasks: 1)
  end

  test "S2, R2: six steps of one agent from two spaces are claimed; the seventh waits, another agent's step does not" do
    runs = 7.times.map { |i| queued_step("Task #{i}") }
    other = Agent.create!(user: @user, name: "Analityk", master_prompt: "You analyse.", executor: @executor)
    other_run = queued_step("Other", agent: other)

    claims = 6.times.map { Scheduler.claim_next }
    assert_equal runs.first(6).map(&:id), claims.map(&:run_id)
    assert_equal [ @agent.id ], claims.map(&:agent_id).uniq
    assert_equal other_run.id, Scheduler.claim_next.run_id, "the blocked seventh is passed over"
    assert_nil Scheduler.claim_next, "the seventh stays queued without a worker"
    assert_equal "queued", runs.last.reload.state

    runs.first.update!(state: "succeeded", finished_at: Time.current) # what the worker does before it releases
    Scheduler.release(claims.first)
    assert_equal runs.last.id, Scheduler.claim_next.run_id, "a freed slot lets it start"
  end

  test "S2, R5: overlapping runs — six at once, the seventh starts when one ends, also after a failure" do
    runs = 7.times.map { |i| queued_step("T#{i}") }
    with_waiting_agent do
      workers = 7.times.map do
        Thread.new do
          claim = Scheduler.claim_next
          Scheduler.process(claim) if claim
        end
      end
      wait_for { started.size == 6 }
      sleep 0.3
      assert_equal 6, started.size, "never a seventh at once"
      assert_equal 6, @agent.running_tasks
      assert AgentStatus.capacity(@agent.running_tasks, @agent.max_parallel_tasks)[:full]
      wait_for { workers.count(&:alive?) == 6 } # the seventh worker found no slot and ended
      assert_equal "queued", runs[6].reload.state

      # One step is stopped (a failure): once its end is saved its slot frees, and the seventh starts.
      assert RunControl.stop!(runs[0].id)
      wait_for { Scheduler.claimed.size == 5 }
      assert_equal "failed", runs[0].reload.state
      claim = Scheduler.claim_next
      assert_equal runs[6].id, claim.run_id
      seventh = Thread.new { Scheduler.process(claim) }
      wait_for { started.include?("T6") }
      %w[T1 T2 T3 T4 T5 T6].each { |task| go(task) }
      (workers + [ seventh ]).each { |t| t.join(20) }
      wait_for { runs[1..].all? { |run| run.reload.finished? } }
    end
    assert_equal [ "succeeded" ] * 6, runs[1..].map { |run| run.reload.state }
    assert_equal 0, @agent.running_tasks
    assert_empty Scheduler.claimed
  end

  test "S3, R4: a lowered limit shows 3/2 and starts nothing until fewer than 2 run" do
    running = 3.times.map { |i| queued_step("R#{i}").tap { |r| r.update!(state: "running", started_at: Time.current) } }
    waiting = queued_step("Waiting")
    assert_equal({ running: 3, limit: 6, full: false, label: "3/6 in progress" }, AgentStatus.capacity(@agent.running_tasks, 6))
    @agent.update!(max_parallel_tasks: 2)
    capacity = AgentStatus.capacity(@agent.running_tasks, @agent.max_parallel_tasks)
    assert_equal "3/2 in progress", capacity[:label]
    assert capacity[:full]
    assert_nil Scheduler.claim_next
    running[0].update!(state: "succeeded", finished_at: Time.current)
    assert_nil Scheduler.claim_next, "2 of 2 still full"
    running[1].update!(state: "failed", finished_at: Time.current)
    assert_equal waiting.id, Scheduler.claim_next.run_id
    assert_equal "6/6 in progress", AgentStatus.capacity(6, 6)[:label]
  end

  test "R2: a calendar run takes its task's agent and counts towards the same limit" do
    @agent.update!(max_parallel_tasks: 1)
    task = @user.tasks.create!(title: "Report", starts_at: Time.current, ends_at: 1.hour.from_now, agent: @agent)
    run = TaskRun.create!(task: task, occurrence_start: task.starts_at, trigger: "manual")
    assert_equal @agent.id, run.agent_id
    step = queued_step("Step")
    assert_equal run.id, Scheduler.claim_next.run_id
    assert_nil Scheduler.claim_next, "the step waits for the calendar run"
    assert_not_equal step.id, Scheduler.claimed.first.run_id
  end

  test "S6: everyone with the agent on their team sees the same total, but only their own activities" do
    admin = create_user(username: "root", role: "admin")
    shared = Agent.create!(user: admin, kind: "shared", name: "Wspólny", master_prompt: "Shared.", executor: @executor)
    bob = create_user(username: "bob")
    [ @user, bob ].each { |u| u.team_roles.create!(agent: shared, role: "member") }
    queued_step("Alice's", agent: shared).update!(state: "running", started_at: Time.current)
    bob_item = bob.work_items.create!(title: "Bob's", state: "planned", space: bob.spaces.create!(name: "Bob", goal: "b"))
    bob_item.epic_steps.create!(position: 1, title: "Bob's", agent: shared)
    StepChain.start(bob_item).update!(state: "running", started_at: Time.current)

    [ @user, bob ].each do |user|
      entry = AgentStatus.json(user)[:agents].find { |a| a[:id] == shared.id }
      assert_equal "2/6 in progress", entry[:capacity][:label], user.username
      assert_equal 0, entry[:activities].count { |a| a[:epic] == (user == bob ? "Alice's" : "Bob's") }, "no details of the other account"
    end
    stranger = create_user(username: "eve")
    assert_nil AgentStatus.json(stranger)[:agents].find { |a| a[:id] == shared.id }, "no counter without the agent"
  end

  test "S3: the status stamp changes when the load or the limit changes" do
    @user.team_roles.create!(agent: @agent, role: "member")
    before = AgentStatus.json(@user)[:stamp]
    @agent.update!(max_parallel_tasks: 3)
    assert_not_equal before, (limited = AgentStatus.json(@user)[:stamp])
    queued_step("Load").update!(state: "running", started_at: Time.current)
    assert_not_equal limited, AgentStatus.json(@user)[:stamp]
  end

  test "R6: two spaces on the same working folder never run a step in it at once" do
    project = File.join(@dirs, "project")
    FileUtils.mkdir_p(project)
    File.symlink(project, File.join(@dirs, "link"))
    a = @user.spaces.create!(name: "Code A", goal: "A", working_dir: project)
    b = @user.spaces.create!(name: "Code B", goal: "B", working_dir: File.join(@dirs, "link"))
    first = queued_step("A", space: a)
    second = queued_step("B", space: b)
    plain = queued_step("Plain")
    assert_equal first.id, Scheduler.claim_next.run_id
    assert_equal plain.id, Scheduler.claim_next.run_id, "steps without a working folder are not held"
    assert_nil Scheduler.claim_next, "the same folder (also through a link) is busy"
    first.update!(state: "succeeded", finished_at: Time.current)
    Scheduler.release(Scheduler.claimed.find { |c| c.run_id == first.id })
    assert_equal second.id, Scheduler.claim_next.run_id
  end

  test "S4, R6: one agent runs steps of spaces with different working folders at once" do
    folders = %w[one two three].map { |name| File.join(@dirs, name).tap { |dir| FileUtils.mkdir_p(dir) } }
    runs = folders.each_with_index.map do |dir, i|
      queued_step("D#{i}", space: @user.spaces.create!(name: "Folder #{i}", goal: "G", working_dir: dir))
    end
    claimed = 3.times.map { Scheduler.claim_next&.run_id }
    assert_equal runs.map(&:id).sort, claimed.compact.sort
    assert_equal [@agent.id], Scheduler.claimed.map(&:agent_id).uniq
  end

  test "S4, R6: each attempt has its own folder; files of the same name do not overwrite each other" do
    runs = 2.times.map { |i| queued_step("F#{i}", space: @spaces[i]) }
    with_waiting_agent do
      %w[F0 F1].each { |task| go(task) }
      threads = 2.times.map { Thread.new { claim = Scheduler.claim_next; Scheduler.process(claim) } }
      threads.each { |t| t.join(20) }
    end
    folders = runs.map { |run| File.join(Rails.application.config.x.runs_dir, run.id.to_s, "work", "shared.txt") }
    assert folders.all? { |f| File.exist?(f) }
    assert_equal 2, folders.uniq.size
  ensure
    runs&.each { |run| FileUtils.rm_rf(File.join(Rails.application.config.x.runs_dir, run.id.to_s)) }
  end

  test "S5, R5: after a restart queued runs are claimed again; a live executor keeps its slot until it ends" do
    queued = queued_step("Queued")
    pid = Process.spawn("sleep", "30", pgroup: true)
    orphan = queued_step("Orphan", space: @spaces[1]).tap { |r| r.update!(state: "running", started_at: Time.current, pid: pid) }
    gone = queued_step("Gone").tap { |r| r.update!(state: "running", started_at: Time.current, pid: 999_999) }
    stale = queued_step("Stale").tap { |r| r.update!(state: "running", started_at: 2.hours.ago, pid: pid) }

    Scheduler.recover!
    assert_equal "running", orphan.reload.state, "its process still runs"
    assert_equal %w[failed failed], [ gone.reload.state, stale.reload.state ], "no process, or past any time limit"
    assert_equal queued.id, Scheduler.claim_next.run_id, "the saved runs are the queue"

    Process.kill("KILL", -pid)
    Process.wait(pid)
    Scheduler.settle_orphans!
    assert_equal "failed", orphan.reload.state
    assert_match "Interrupted", orphan.error
  ensure
    begin
      Process.kill("KILL", -pid) if pid
    rescue Errno::ESRCH
      nil
    end
  end

  test "R7: workers follow the highest limit; both connection pools cover them" do
    assert_equal Rails.application.config.x.run_workers + 6, Scheduler.worker_target
    @agent.update!(max_parallel_tasks: 10)
    assert_equal Rails.application.config.x.run_workers + 10, Scheduler.worker_target
    @agent.update!(enabled: false)
    assert_equal Rails.application.config.x.run_workers + 6, Scheduler.worker_target, "disabled agents do not count"

    most = Rails.application.config.x.run_workers + Agent::PARALLEL_RANGE.max + Integer(ENV.fetch("RAILS_MAX_THREADS", 3)) + 2
    [ ActiveRecord::Base, AuditRecord ].each do |model|
      assert_operator model.connection_pool.size, :>=, most, model.name
    end
  end

  # Step 5 of the epic: the acceptance tests of S1–S5 with a stand-in executor that really overlaps.

  test "S1: a new agent takes 6, a changed limit counts for the next start at once" do
    fresh = Agent.create!(user: @user, name: "Nowy", master_prompt: "New.", executor: @executor)
    assert_equal 6, fresh.reload.max_parallel_tasks
    @agent.update!(max_parallel_tasks: 2)
    3.times { |i| queued_step("L#{i}") }
    assert_equal 2, 3.times.map { Scheduler.claim_next }.compact.size, "2 of 3 under a limit of 2"
    @agent.update!(max_parallel_tasks: 3)
    assert Scheduler.claim_next, "a raised limit lets the third start without a restart"
  end

  test "S2, S4, R6: six tasks of one agent in six spaces, each in its own folder, run at once; the seventh waits" do
    spaces = 7.times.map { |i| folder_space(i) }
    runs = spaces.each_with_index.map { |space, i| queued_step("S#{i}", space: space) }
    with_waiting_agent do
      threads = workers(7)
      wait_for { started.size == 6 }
      sleep 0.3
      assert_equal %w[S0 S1 S2 S3 S4 S5], started, "six at once, never a seventh"
      assert_equal 6, @agent.running_tasks
      assert_equal 6, runs.first(6).map { |run| run.reload.state }.count("running")
      assert_equal "queued", runs[6].reload.state
      6.times { |i| assert_equal File.realpath(spaces[i].working_dir), pwd_of("S#{i}"), "S#{i} works in its space's folder" }

      go("S0")
      wait_for { runs[0].reload.finished? }
      claim = Scheduler.claim_next
      assert_equal runs[6].id, claim.run_id, "the freed slot goes to the seventh"
      threads << Thread.new { Scheduler.process(claim) }
      wait_for { started.include?("S6") }
      %w[S1 S2 S3 S4 S5 S6].each { |task| go(task) }
      threads.each { |t| t.join(20) }
    end
    assert_equal [ "succeeded" ] * 7, runs.map { |run| run.reload.state }
    spaces.each_with_index do |space, i|
      assert_equal "same name S#{i}\n", File.read(File.join(space.working_dir, "shared.txt")), "no task wrote into another's folder"
    end
    assert_equal 0, @agent.running_tasks
  end

  test "S2, R5: an executor that fails frees its slot and the queued task starts" do
    @agent.update!(max_parallel_tasks: 2)
    failing = queued_step("Fail0")
    holding = queued_step("Hold1", space: @spaces[1])
    waiting = queued_step("Wait2")
    with_waiting_agent do
      threads = workers(3)
      wait_for { started.size == 2 }
      assert_equal "queued", waiting.reload.state, "2 of 2 slots taken"
      go("Fail0")
      wait_for { failing.reload.finished? }
      assert_equal "failed", failing.state
      assert_match "boom in Fail0", failing.error.to_s + failing.output.to_s
      wait_for { Scheduler.claimed.size == 1 }
      claim = Scheduler.claim_next
      assert_equal waiting.id, claim.run_id, "the failure freed the slot"
      threads << Thread.new { Scheduler.process(claim) }
      %w[Hold1 Wait2].each { |task| go(task) }
      threads.each { |t| t.join(20) }
    end
    assert_equal %w[succeeded succeeded], [ holding.reload.state, waiting.reload.state ]
    assert_empty Scheduler.claimed
  end

  test "R6: a space whose folder is gone fails the step and frees the slot" do
    @agent.update!(max_parallel_tasks: 1)
    space = folder_space("gone")
    lost = queued_step("Lost", space: space)
    nextone = queued_step("Next")
    FileUtils.rm_rf(space.working_dir)
    with_waiting_agent do
      go("Next")
      Scheduler.process(Scheduler.claim_next)
      assert_equal "failed", lost.reload.state
      assert_match "Working folder not found", lost.error
      assert_equal nextone.id, (claim = Scheduler.claim_next).run_id
      Scheduler.process(claim)
    end
    assert_equal "succeeded", nextone.reload.state
  ensure
    FileUtils.rm_rf(File.join(Rails.application.config.x.runs_dir, nextone.id.to_s)) if nextone
  end

  test "S4, R6: a retry gets its own folder and leaves the failed attempt's files alone" do
    failed = queued_step("Fail9")
    with_waiting_agent do
      go("Fail9")
      Scheduler.process(Scheduler.claim_next)
      assert_equal "failed", failed.reload.state
      first_folder = pwd_of("Fail9")
      failed.epic_step.update!(state: "queued") # spec 040: the director's retry, as StepReviewer creates it
      failed.work_item.reload.update!(state: "planned", blocked_reason: nil)
      retry_run = TaskRun.create!(user: @user, work_item: failed.work_item, epic_step: failed.epic_step, agent: @agent, purpose: "epic_step",
                                  trigger: "retry", occurrence_start: Time.current, state: "queued", attempt: 2)
      @runs = [ failed, retry_run ]
      Scheduler.process(Scheduler.claim_next)
      folders = @runs.map { |run| File.realpath(File.join(Rails.application.config.x.runs_dir, run.id.to_s, "work")) }
      assert_equal folders[0], first_folder
      assert_equal folders[1], pwd_of("Fail9"), "the retry ran in a folder of its own"
      assert_not_equal folders[0], folders[1]
      assert_equal "same name Fail9\n", File.read(File.join(folders[0], "shared.txt")), "the first attempt's file is kept"
    end
  ensure
    @runs&.each { |run| FileUtils.rm_rf(File.join(Rails.application.config.x.runs_dir, run.id.to_s)) }
  end

  test "S5, R7: at a limit of 10 ten tasks run at once while other threads read and write both databases" do
    @agent.update!(max_parallel_tasks: 10)
    runs = 11.times.map { |i| queued_step("X#{i}") }
    with_waiting_agent do
      threads = workers(11)
      wait_for(20) { started.size == 10 }
      assert_equal 10, @agent.running_tasks
      assert_equal "queued", runs[10].reload.state
      changes = DataChange.count
      others = 4.times.map do |i|
        Thread.new do
          Rails.application.executor.wrap { @user.spaces.create!(name: "Busy #{i}", goal: "G") } # changelogged: writes the audit chain
        end
      end
      others.each { |t| assert t.join(15), "a request-like thread waited for a connection" }
      assert_equal 4, Space.where("name LIKE 'Busy %'").count
      assert_operator DataChange.count, :>=, changes + 4
      (0..9).each { |i| go("X#{i}") }
      threads.each { |t| t.join(30) }
    end
    assert_equal [ "succeeded" ] * 10, runs.first(10).map { |run| run.reload.state }
    assert_equal "queued", runs[10].reload.state
  ensure
    runs&.each { |run| FileUtils.rm_rf(File.join(Rails.application.config.x.runs_dir, run.id.to_s)) }
  end
end
