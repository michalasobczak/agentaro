require "test_helper"

# Spec 033: the autonomy slider — levels, step decisions and assumptions, planning by level (G1–G6, R1–R5, S1–S4).
class AutonomyTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @executor = Executor.create!(name: "Claude", preset: "claude_code")
    @director = Agent.create!(user: @user, name: "Anna", master_prompt: "You direct.", executor: @executor)
    @writer = Agent.create!(user: @user, name: "Pisarz", master_prompt: "You write.", executor: @executor)
    @user.team_roles.create!(agent: @director, role: "director")
    @user.team_roles.create!(agent: @writer, role: "member", role_text: "writer")
    @space = @user.spaces.create!(name: "Raporty", kind: "team")
    @item = @user.work_items.create!(title: "Raport", state: "planned", space: @space)
    @item.epic_steps.create!(position: 1, title: "Research", agent: @writer)
    @item.epic_steps.create!(position: 2, title: "Write", agent: @writer)
    @dir = Dir.mktmpdir
  end

  teardown { FileUtils.rm_rf(@dir) }

  # A stand-in "claude": the n-th call for a task answers the file out-<task>-<n> if there is one, else "Answer
  # for <task>". Every prompt is kept as prompt-<task>-<n>.
  def with_agent
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "claude"), <<~SH)
        #!/bin/sh
        input=$(cat)
        task=$(printf '%s' "$input" | sed -n 's/^Your task: //p' | head -1)
        n=$(cat "#{@dir}/count-$task" 2>/dev/null || echo 0)
        n=$((n + 1)); echo $n > "#{@dir}/count-$task"
        printf '%s' "$input" > "#{@dir}/prompt-$task-$n"
        if [ -f "#{@dir}/out-$task-$n" ]; then cat "#{@dir}/out-$task-$n"; else echo "Answer for $task"; fi
      SH
      File.chmod(0o755, File.join(bin, "claude"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      yield
    ensure
      ENV["PATH"] = original
    end
  end

  def answer(task, n, text) = File.write(File.join(@dir, "out-#{task}-#{n}"), text)
  def prompt(task, n) = File.read(File.join(@dir, "prompt-#{task}-#{n}"))

  def run_queued(limit = 12)
    limit.times do
      run = TaskRun.where(state: "queued", purpose: "epic_step").order(:id).first or break
      StepChain.new(run).perform!
    end
  end

  def decision_line(important: false, always_ask: false, options: [ "PDF", "Markdown" ], recommended: "Markdown")
    "Partial work.\n#{Autonomy::DECISION_PREFIX} #{{ question: "PDF czy Markdown?", options: options, recommended: recommended, why: "Łatwiej edytować.", important: important, always_ask: always_ask }.to_json}\n"
  end

  # --- Levels and parsing --------------------------------------------------------------------------

  test "G1, G2, R1: the owner's default is Ważne pytaj; a space's own level wins" do
    assert_equal 2, Autonomy.level_for(@space)
    @user.update!(autonomy_level: 3)
    assert_equal 3, Autonomy.level_for(@space.reload)
    @space.update!(autonomy_level: 1)
    assert_equal 1, Autonomy.level_for(@space)
    assert_not @space.update(autonomy_level: 7)
    assert_not @user.update(autonomy_level: 0)
  end

  test "R5: decision lines are data; malformed ones are ignored, the recommendation is one of the options" do
    d = Autonomy.parse_decision(decision_line(important: true))
    assert_equal [ "PDF czy Markdown?", %w[PDF Markdown], "Markdown", true, false ], d.values_at(:question, :options, :recommended, :important, :always_ask)
    assert_nil Autonomy.parse_decision("#{Autonomy::DECISION_PREFIX} {not json")
    assert_nil Autonomy.parse_decision("#{Autonomy::DECISION_PREFIX} {\"question\": \"x\", \"options\": [\"only one\"]}")
    assert_nil Autonomy.parse_decision("no decision here")
    assert_equal "A", Autonomy.parse_decision("#{Autonomy::DECISION_PREFIX} {\"question\": \"q\", \"options\": [\"A\", \"B\"], \"recommended\": \"rm -rf /\"}")[:recommended]
    assert_equal [ "Format Markdown.", "Po polsku." ], Autonomy.parse_assumptions("x\n#{Autonomy::ASSUMED_PREFIX} Format Markdown.\n  #{Autonomy::ASSUMED_PREFIX} Po polsku.\n")
  end

  test "G4: every step prompt carries the level and the always-ask list" do
    with_agent { StepChain.start(@item); run_queued }
    text = prompt("Research", 1)
    assert_match "autonomy level: Ważne pytaj", text
    Autonomy::ALWAYS_ASK.each { |line| assert_includes text, line }
    assert_match Autonomy::DECISION_PREFIX, text
  end

  # --- Steps: S3, S4 ---------------------------------------------------------------------------------

  test "S3: at Ważne pytaj a small choice is assumed, the step runs again with it and the epic finishes; the report lists it" do
    answer("Research", 1, decision_line(important: false))
    answer("Research", 2, "Raport w Markdown.\n#{Autonomy::ASSUMED_PREFIX} Odbiorca: zespół.\n")
    with_agent { StepChain.start(@item); run_queued }
    assert_equal "done", @item.reload.state
    decisions = @item.step_decisions.order(:id)
    assert_equal [ [ "assumption", "Markdown" ], [ "assumption", "Odbiorca: zespół." ] ], decisions.map { |d| [ d.answered_by, d.answer ] }
    rerun = prompt("Research", 2)
    assert_match "PDF czy Markdown? → Markdown (taken as your recommendation)", rerun
    assert_match "Your previous answer to this step, before the decision", rerun
    assert_match "Partial work.", rerun
    assert_match "Assumed: PDF czy Markdown? → Markdown; Odbiorca: zespół.", @user.chat_messages.last.content
    assert_empty WorkItem.block_notices
  end

  test "S3, G3, R3: an important decision blocks the epic with the question; Try again cannot skip it; the owner's answer resumes the step" do
    answer("Research", 1, decision_line(important: true))
    with_agent do
      StepChain.start(@item)
      run_queued
      @item.reload
      assert_equal [ "blocked", "waiting", "pending" ], [ @item.state, @item.epic_steps.first.state, @item.epic_steps.second.state ]
      assert_match "Step 1 \"Research\" asks: PDF czy Markdown?", @item.blocked_reason
      assert_match(/step 1 asks: PDF czy Markdown\?\nOptions: 1\) PDF; 2\) Markdown \(recommended\)/, @user.chat_messages.last.content)

      StepChain.resume(@item)
      assert_equal "blocked", @item.reload.state, "Try again does not run a step that waits for an answer"
      assert_equal 1, TaskRun.where(purpose: "epic_step").count

      decision = @item.step_decisions.pending.sole
      assert decision.answer_by_owner!("PDF, proszę")
      assert_not decision.answer_by_owner!("Markdown"), "one winner"
      run_queued
    end
    assert_equal "done", @item.reload.state
    assert_match "PDF czy Markdown? → PDF, proszę (your owner's answer)", prompt("Research", 2)
  end

  test "S4: at Decyduj an always-ask decision still waits for the owner; a small one is assumed" do
    @user.update!(autonomy_level: 3)
    answer("Research", 1, decision_line(important: true)) # important, but not always-ask: decided
    answer("Research", 2, decision_line(always_ask: true, options: [ "Wyślij e-mail", "Nie wysyłaj" ], recommended: "Wyślij e-mail"))
    with_agent do
      StepChain.start(@item)
      run_queued
    end
    @item.reload
    assert_equal "blocked", @item.state
    assert_equal [ "assumption", nil ], @item.step_decisions.order(:id).map(&:answered_by)
    assert @item.step_decisions.pending.sole.always_ask
  end

  test "G1: at Pytaj even a small decision waits for the owner" do
    @space.update!(autonomy_level: 1)
    answer("Research", 1, decision_line(important: false))
    with_agent { StepChain.start(@item); run_queued }
    assert_equal "blocked", @item.reload.state
    assert_match "your owner wants to be asked".downcase, prompt("Research", 1).downcase
  end

  test "a step that keeps asking is taken as it is after #{Autonomy::MAX_DECISIONS} decisions" do
    (1..5).each { |n| answer("Research", n, decision_line(important: false)) }
    with_agent { StepChain.start(@item); run_queued }
    assert_equal "done", @item.reload.state
    assert_equal Autonomy::MAX_DECISIONS, @item.step_decisions.where.not(question: nil).count
  end

  test "cancelling an epic with a question waiting closes the question and the step" do
    answer("Research", 1, decision_line(important: true))
    with_agent { StepChain.start(@item); run_queued }
    @item.reload.cancel!
    assert_equal [ "cancelled", "cancelled" ], @item.epic_steps.map(&:state)
    assert_empty @item.step_decisions.pending
  end

  test "G5: correcting an assumption becomes an active fact about the space; secrets are refused" do
    d = @item.step_decisions.create!(status: "answered", answered_by: "assumption", answer: "Format Markdown.")
    fact = d.correct!("Zawsze PDF.")
    assert_equal [ "space", @space.id, "active", "Instead of assuming \"Format Markdown.\": Zawsze PDF." ], fact.values_at(:subject_type, :subject_id, :status, :statement)
    assert d.reload.corrected_at
    other = @item.step_decisions.create!(status: "answered", answered_by: "assumption", answer: "x")
    assert_raises(ActiveRecord::RecordInvalid) { other.correct!("key sk-ant-api03-AbCdEfGhIjKlMnOpQrStUvWxYz0123456789") }
    assert_nil other.reload.corrected_at, "nothing saved"
  end

  # --- Planning: S1, S2 ------------------------------------------------------------------------------

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

  def plan(item)
    run = ManagementRunner.queue!(user: @user, purpose: "director", work_item: item, agent: @director)
    ManagementRunner.new(run).perform!
  end

  test "S1: at Pytaj the director asks clarifying questions first, then plans, and the plan waits for Approve" do
    @space.update!(autonomy_level: 1)
    @item.update!(state: "done") # spec 037: the earlier epic of the space would go first
    item = @user.work_items.create!(title: "Przygotuj raport o backupach", state: "new", space: @space)
    plan_json = { summary: "Raport.", steps: [ { title: "Research", description: "x", agent: @writer.id } ] }
    with_director({ blocked: "Dla kogo raport? Jaki format?" }, plan_json) do
      plan(item)
      assert_equal [ "blocked", 1 ], [ item.reload.state, item.clarifications ]
      assert_match "ask at most 3 short questions", File.read(File.join(@dir, "dprompt-1"))
      item.update!(state: "new", blocked_reason: nil, description: "Dla zespołu, Markdown.")
      plan(item)
      assert_match "has answered your questions: plan now", File.read(File.join(@dir, "dprompt-2"))
    end
    item.reload
    assert_equal [ "planned", true ], [ item.state, item.awaiting_approval ]
    assert_empty StepChain.start_due, "nothing runs before Approve"
    assert_nil StepChain.queue_next(item)
    assert_match "waiting for your approval", @user.chat_messages.last.actions_summary
    assert item.approve_plan!
    assert_not item.approve_plan!, "approved once"
    assert_equal "queued", item.epic_steps.first.reload.state
  end

  test "S2: at Decyduj the director plans without asking and records its assumptions" do
    @user.update!(autonomy_level: 3)
    item = @user.work_items.create!(title: "Przygotuj raport o backupach", state: "new", space: @space)
    with_director({ summary: "Raport.", steps: [ { title: "Research", description: "x", agent: @writer.id } ], assumptions: [ "Format Markdown.", "" ] }) do
      plan(item)
      assert_match "do not ask", File.read(File.join(@dir, "dprompt-1"))
    end
    item.reload
    assert_equal [ "planned", false ], [ item.state, item.awaiting_approval ]
    assert_equal [ "Format Markdown." ], item.step_decisions.assumptions.map(&:answer)
    assert_match "Assumed: Format Markdown.", @user.chat_messages.last.actions_summary
  end
end
