require "test_helper"

# Spec 040: the epic page shows each step's limit and the director's decisions with earlier instructions (G1, G2, R6);
# the live view shows a running step's processes and its limit (G3); the chat stops a step's process only on the
# owner's words and only one of the step's own (G4, R3).
class StepReviewPagesTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    executor = Executor.create!(name: "Claude", preset: "claude_code")
    @director = Agent.create!(user: @user, name: "Anna", master_prompt: "You direct.", executor: executor)
    @writer = Agent.create!(user: @user, name: "Pisarz", master_prompt: "You write.", executor: executor)
    @user.team_roles.create!(agent: @director, role: "director")
    @space = @user.spaces.create!(name: "Gra", kind: "team")
    @item = @user.work_items.create!(title: "MVP", space: @space, state: "planned", started_at: 10.minutes.ago)
    @step = @item.epic_steps.create!(position: 1, title: "Build", description: "npm run compile", agent: @writer, state: "running", time_limit_minutes: 90)
    @run = TaskRun.create!(user: @user, work_item: @item, epic_step: @step, agent: @writer, purpose: "epic_step", trigger: "retry",
                           occurrence_start: Time.current, state: "running", started_at: 2.minutes.ago, attempt: 2)
    @step.step_reviews.create!(user: @user, work_item: @item, kind: "failure", status: "decided", decision: "change",
                               reason: "Skrypt <b>build</b> nie istnieje.", previous_description: "npm run build", time_limit_minutes: 90)
    @pid = Process.spawn("sleep", "300", pgroup: true) # a step's process is never in the server's group
    info = ProcessTracker.snapshot.find { |p| p.pid == @pid }
    @dir = LiveLog.dir_for(@run.id).tap { |d| FileUtils.mkdir_p(d) }
    ProcessTracker.write(@dir, [ { "pid" => @pid, "started" => info.started, "command" => "sleep 300", "since" => 3.minutes.ago.iso8601, "alive" => true } ])
    sign_in(@user)
  end

  teardown do
    Process.kill("KILL", @pid) rescue nil
    Process.wait(@pid) rescue nil
    FileUtils.rm_rf(@dir)
  end

  test "G1, G2, R6: the epic page shows the limit and the decision with the earlier instructions, escaped; no inline style" do
    get work_item_path(@item)
    assert_select "#step-1", text: /limit 90 min/
    assert_select "#step-1 .step-reviews li", text: /The director retried the step with changed instructions, limit 90 min: Skrypt <b>build<\/b> nie istnieje\./
    assert_select "#step-1 .step-reviews details p", text: "npm run build"
    assert_select "[style]", 0
  end

  test "G3: the live view shows the running step's processes and its limit" do
    get live_director_path(step: @step.id), as: :json
    body = response.parsed_body
    assert_equal 90, body.dig("step", "limit")
    assert_equal [ "sleep 300" ], body["processes"].map { |p| p["command"] }
    assert_equal [ "The director retried the step with changed instructions: Skrypt <b>build</b> nie istnieje." ], body["decisions"].map { |d| d["text"] }
  end

  def chat(content, actions)
    @user.chat_messages.create!(author: "user", content: content)
    Dir.mktmpdir do |bin|
      [ { reply: "Dobrze.", actions: actions }, { reply: "ok", actions: actions } ].each_with_index { |a, i| File.write(File.join(bin, "answer-#{i + 1}"), a.to_json) }
      File.write(File.join(bin, "claude"), "#!/bin/sh\ncat > /dev/null\nn=$(cat #{bin}/n 2>/dev/null || echo 0); n=$((n + 1)); echo $n > #{bin}/n\ncat #{bin}/answer-$n\n")
      File.chmod(0o755, File.join(bin, "claude"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      run = ManagementRunner.chat!(@user)
      ManagementRunner.new(run.reload).perform!
    ensure
      ENV["PATH"] = original
    end
    @user.chat_messages.where(author: "director").order(:id).last
  end

  def alive?(pid)
    Process.waitpid(pid, Process::WNOHANG) rescue nil
    Process.kill(0, pid) && !`ps -o stat= -p #{pid}`.strip.start_with?("Z")
  rescue Errno::ESRCH
    false
  end

  test "G4, R3: the director sees the step's processes and stops one only when the owner asks, and only its own" do
    action = [ { type: "stop_process", run: @run.id, pid: @pid } ]
    chat("Jak idzie build?", action)
    assert alive?(@pid), "no stop without the owner's words"
    prompt = TaskRun.where(purpose: "chat").order(:id).last.model_calls.first.prompt_text
    assert_match "process of run #{@run.id}, pid #{@pid}: sleep 300", prompt
    assert_match "(limit 90 min)", prompt

    other = Process.spawn("sleep", "302", pgroup: true)
    chat("Zabij ten proces.", [ { type: "stop_process", run: @run.id, pid: other } ])
    assert alive?(other), "R3: not a process of the step"
    Process.kill("KILL", other)

    reply = chat("Zabij ten wiszący sleep.", action)
    assert_not alive?(@pid)
    assert_match "Stopped: sleep 300", reply.actions_summary
  end
end
