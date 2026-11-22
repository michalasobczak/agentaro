require "test_helper"

# Spec 041: the work tempo in planning (G4, G5, R4–R6, S5–S7) and the conversation style rule (G3, R2, R3).
class WorkTempoTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    executor = Executor.create!(name: "Claude", preset: "claude_code")
    @director = Agent.create!(user: @user, name: "Anna", master_prompt: "You direct.", executor: executor)
    @writer = Agent.create!(user: @user, name: "Pisarz", master_prompt: "You write.", executor: executor)
    @checker = Agent.create!(user: @user, name: "Tester", master_prompt: "You check.", executor: executor)
    @user.team_roles.create!(agent: @director, role: "director")
    @user.team_roles.create!(agent: @writer, role: "member", role_text: "writer")
    @user.team_roles.create!(agent: @checker, role: "member", role_text: "tester")
    @space = @user.spaces.create!(name: "Raporty", kind: "team")
    @dir = Dir.mktmpdir
  end

  teardown { FileUtils.rm_rf(@dir) }

  def with_director(*answers)
    Dir.mktmpdir do |bin|
      answers.each_with_index { |a, i| File.write(File.join(@dir, "director-#{i + 1}"), a.to_json) }
      File.write(File.join(bin, "claude"), <<~SH)
        #!/bin/sh
        input=$(cat)
        n=$(cat "#{@dir}/dcount" 2>/dev/null || echo 0)
        n=$((n + 1)); echo $n > "#{@dir}/dcount"
        printf '%s' "$input" > "#{@dir}/dprompt-$n"
        cat "#{@dir}/director-$n"
      SH
      File.chmod(0o755, File.join(bin, "claude"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      yield
    ensure
      ENV["PATH"] = original
    end
  end

  def dprompt(n) = File.read(File.join(@dir, "dprompt-#{n}"))

  def plan(item)
    run = ManagementRunner.queue!(user: @user, purpose: "director", work_item: item, agent: @director)
    ManagementRunner.new(run).perform!
  end

  def item(title = "Przygotuj raport") = @user.work_items.create!(title: title, state: "new", space: @space)
  def step(title, agent = @writer) = { title: title, description: "x", agent: agent.id }

  test "S4: Dorosły and Normalnie by default; a space's own tempo wins; invalid values are refused" do
    assert_equal [ 2, 2 ], [ User.new.chat_style, User.new.work_tempo ]
    assert_equal [ 2, 2 ], [ @user.chat_style, @user.work_tempo ]
    assert_equal 2, WorkTempo.level_for(@space)
    @user.update!(work_tempo: 3)
    assert_equal 3, WorkTempo.level_for(@space.reload)
    @space.update!(work_tempo: 1)
    assert_equal 1, WorkTempo.level_for(@space)
    assert_not @space.update(work_tempo: 4)
    assert_not @user.update(work_tempo: 0)
    assert_not @user.update(chat_style: 9)
  end

  test "Normalnie: the plan prompt is as before, 1 to 10 steps" do
    with_director({ summary: "Raport.", steps: [ step("Research"), step("Write") ] }) { plan(item) }
    assert_match "Rules: 1 to #{ManagementRunner::MAX_STEPS} steps, in the order they should run", dprompt(1)
    assert_match "Tempo: Normalnie.", dprompt(1)
    assert_no_match(/Tempo: Turbo|exactly 1 step/, dprompt(1))
  end

  test "S5, R5: at Turbo the plan must have exactly 1 step; a 2-step plan is refused and asked again" do
    @user.update!(work_tempo: 3)
    epic = item
    with_director({ summary: "Raport.", steps: [ step("Research"), step("Write") ] }, { summary: "Raport.", steps: [ step("Całość") ] }) { plan(epic) }
    assert_match "Rules: exactly 1 step;", dprompt(1)
    assert_match "Tempo: Turbo. Plan exactly 1 step, for the one member best fitted", dprompt(1)
    assert_match "the plan must have exactly 1 step", dprompt(2)
    assert_equal [ "planned", [ "Całość" ] ], [ epic.reload.state, epic.epic_steps.pluck(:title) ]
  end

  test "S5, R6: at Pytaj with Turbo there are no clarifying questions, and the plan still waits for approval" do
    @user.update!(work_tempo: 3, autonomy_level: 1)
    epic = item
    with_director({ summary: "Raport.", steps: [ step("Całość") ] }) { plan(epic) }
    assert_match "do not ask clarifying questions", dprompt(1)
    assert_no_match "ask at most 3 short questions", dprompt(1)
    assert_match "approves the plan before it starts", dprompt(1)
    assert_equal [ "planned", true ], [ epic.reload.state, epic.awaiting_approval ]
  end

  test "S6: at Dokładnie the plan prompt asks for smaller steps and a checking step last" do
    @space.update!(work_tempo: 1)
    with_director({ summary: "Raport.", steps: [ step("Research"), step("Write"), step("Check", @checker) ] }) { plan(item) }
    assert_match "Tempo: Dokładnie. Split the work into small steps", dprompt(1)
    assert_match "The last step checks the work", dprompt(1)
  end

  test "S7: a space's own tempo plans by it, another space by the owner's default" do
    @user.update!(work_tempo: 3)
    other = @user.spaces.create!(name: "Kod", kind: "team", work_tempo: 2)
    with_director({ summary: "A.", steps: [ step("Research"), step("Write") ] }) { plan(@user.work_items.create!(title: "Kod", state: "new", space: other)) }
    assert_match "Tempo: Normalnie.", dprompt(1)
    assert_equal 2, other.work_items.last.epic_steps.count
  end

  test "R4: the director's replan after a failed step follows the tempo; at Turbo only 1 step" do
    @user.update!(work_tempo: 3)
    epic = item
    failed = epic.epic_steps.create!(position: 1, title: "Build", agent: @writer, state: "reviewing")
    run = TaskRun.create!(user: @user, work_item: epic, epic_step: failed, agent: @writer, purpose: "epic_step", trigger: "scheduled", occurrence_start: Time.current, state: "failed")
    review = StepReview.create!(user: @user, work_item: epic, epic_step: failed, task_run: run, kind: "failure")
    reviewer = StepReviewer.new(run)
    { :@review => review, :@item => epic, :@step => failed, :@user => @user }.each { |k, v| reviewer.instance_variable_set(k, v) }
    assert_match "A replan follows the tempo: Tempo: Turbo.", reviewer.send(:failure_rules)
    two = { "steps" => [ step("A").stringify_keys, step("B").stringify_keys ] }
    error = assert_raises(StepReviewer::Invalid) { reviewer.send(:check, "replan", two) }
    assert_match "a replan must have exactly 1 step", error.message
    assert_equal 1, reviewer.send(:check, "replan", { "steps" => [ step("A").stringify_keys ] })[:steps].size
  end

  test "G3, R3: each style has its own rule, which sets the words, not the length" do
    assert_match "Dziecko — talk as to a child", ChatStyle.rule(1, "ola")
    assert_match "Dorosły — plain language for an adult", ChatStyle.rule(2, "ola")
    assert_match "Inżynier — precise technical language", ChatStyle.rule(3, "ola")
    assert_match "not the length of your reply", ChatStyle.rule(2, "ola")
  end
end
