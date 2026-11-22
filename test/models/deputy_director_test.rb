require "test_helper"

# Spec 043, G4–G7: the deputy director, waiting without one, the director's view of limits, and reassign_step.
class DeputyDirectorTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @claude = Executor.create!(name: "Claude", preset: "claude_code")
    @spare = Executor.create!(name: "Spare", preset: "claude_code") # another subscription, the same fake program
    mk = ->(name, executor) { Agent.create!(user: @user, name: name, master_prompt: "You are #{name}.", executor: executor) }
    @director, @writer = mk.("Dyrektor", @claude), mk.("Pisarz", @claude)
    @deputy_agent, @spare_writer = mk.("Zastepca", @spare), mk.("Kodeks", @spare)
    @user.team_roles.create!(agent: @director, role: "director")
    @user.team_roles.create!(agent: @writer, role: "member", role_text: "writer")
    @user.team_roles.create!(agent: @spare_writer, role: "member", role_text: "coder")
    @log = Dir.mktmpdir
  end

  teardown { FileUtils.rm_rf(@log) }

  # A stand-in "claude": each call appends who was asked (the master prompt's name) to calls; answers `answer`.
  def with_claude(answer)
    File.write(File.join(@log, "answer"), answer.is_a?(String) ? answer : answer.to_json)
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "claude"), <<~SH)
        #!/bin/sh
        input=$(cat)
        who=$(printf '%s' "$input" | sed -n 's/^You are \\([A-Za-z]*\\)\\..*/\\1/p' | head -1)
        echo "$who" >> "#{@log}/calls"
        printf '%s' "$input" > "#{@log}/prompt-$who"
        cat "#{@log}/answer"
      SH
      File.chmod(0o755, File.join(bin, "claude"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      yield
    ensure
      ENV["PATH"] = original
    end
  end

  def calls = File.exist?(File.join(@log, "calls")) ? File.read(File.join(@log, "calls")).split : []

  def at_limit!(executor, until_at) = UsageLimit.record!(executor, { "windows" => [], "reached" => true, "window" => "five_hour", "resets_at" => until_at.iso8601 })

  def chat(text)
    @user.chat_messages.create!(author: "user", content: text)
    ManagementRunner.chat!(@user)
    10.times do
      run = TaskRun.where(state: "queued", purpose: %w[chat director]).order(:id).first or break
      ManagementRunner.new(run).perform!
    end
  end

  test "S3, G4: while the director's tool is at its limit the deputy answers, with the note, and the director is not called" do
    @user.team_roles.create!(agent: @deputy_agent, role: "deputy")
    travel_to Time.zone.local(2026, 11, 22, 12, 0) do
      at_limit!(@claude, Time.zone.local(2026, 11, 22, 15, 10))
      with_claude(reply: "Wszystko idzie zgodnie z planem.", actions: []) { chat("Co się dzieje?") }
    end
    assert_equal [ "Zastepca" ], calls
    messages = @user.chat_messages.ordered.last(2).map { |m| [ m.author, m.content ] }
    assert_equal [ "system", "Zastepca, the deputy director, answers: the director's Claude Code is at its usage limit until 15:10." ], messages[0]
    assert_equal [ "director", "Wszystko idzie zgodnie z planem." ], messages[1]
  end

  test "G4: a director call that ends on a limit is sent once more, to the deputy" do
    @user.team_roles.create!(agent: @deputy_agent, role: "deputy")
    limit = { type: "result", is_error: true, result: "You've hit your 5-hour limit · resets 11pm (Europe/Warsaw)" }.to_json
    travel_to Time.zone.local(2026, 11, 22, 12, 0) do
      File.write(File.join(@log, "limit"), limit)
      Dir.mktmpdir do |bin|
        File.write(File.join(bin, "claude"), <<~SH)
          #!/bin/sh
          input=$(cat)
          if printf '%s' "$input" | grep -q "^You are Dyrektor"; then echo Dyrektor >> "#{@log}/calls"; cat "#{@log}/limit"; exit 1; fi
          echo Zastepca >> "#{@log}/calls"
          echo '{"reply": "Jestem zastępcą.", "actions": []}'
        SH
        File.chmod(0o755, File.join(bin, "claude"))
        original = ENV["PATH"]
        ENV["PATH"] = "#{bin}:#{original}"
        chat("Hej")
      ensure
        ENV["PATH"] = original
      end
      assert_equal %w[Dyrektor Zastepca], calls
      assert_equal "Jestem zastępcą.", @user.chat_messages.where(author: "director").last.content
      assert_match "until 23:00", @user.chat_messages.where(author: "system").last.content
    end
  end

  test "S4, G5: without a deputy the chat says until when, and nothing is called" do
    travel_to Time.zone.local(2026, 11, 22, 12, 0) do
      at_limit!(@claude, Time.zone.local(2026, 11, 22, 15, 10))
      with_claude(reply: "x", actions: []) { chat("Co się dzieje?") }
    end
    assert_empty calls
    assert_equal "No answer from the director: the director's Claude Code is at its usage limit until 15:10; choose a deputy director on the Team page to talk meanwhile.",
                 @user.chat_messages.ordered.last.content
  end

  test "G6: the director sees which members are at a limit" do
    travel_to Time.zone.local(2026, 11, 22, 12, 0) do
      at_limit!(@spare, Time.zone.local(2026, 11, 22, 15, 10))
      with_claude(reply: "ok", actions: []) { chat("Kto jest wolny?") }
    end
    prompt = File.read(File.join(@log, "prompt-Dyrektor"))
    assert_match "Kodeks, role: coder; its Claude Code usage limit reached until 15:10", prompt
    assert_no_match(/Pisarz, role: writer; its/, prompt)
  end

  test "S5, G7: a step waiting for a usage-limit retry goes to another member and starts now" do
    item = @user.work_items.create!(title: "Backups", state: "planned", started_at: 5.minutes.ago)
    step = item.epic_steps.create!(position: 1, title: "Research", agent: @writer, state: "queued")
    TaskRun.create!(user: @user, work_item: item, epic_step: step, agent: @writer, purpose: "epic_step", trigger: "scheduled",
                    occurrence_start: 5.minutes.ago, state: "failed", attempt: 1, failure_kind: "usage_limit")
    waiting = TaskRun.create!(user: @user, work_item: item, epic_step: step, agent: @writer, purpose: "epic_step", trigger: "retry",
                              occurrence_start: Time.current, state: "queued", attempt: 2, retry_at: 3.hours.from_now)
    with_claude(reply: "Przekazuję krok Kodeksowi.", actions: [ { type: "reassign_step", id: item.id, step: 1, agent: @spare_writer.id } ]) do
      chat("Przekaż krok 1 Kodeksowi")
    end
    assert_equal [ @spare_writer, @spare_writer ], [ step.reload.agent, waiting.reload.agent ]
    assert_nil waiting.retry_at, "it starts now"
    assert_match "goes to Kodeks and starts now", @user.chat_messages.where(author: "director").last.actions_summary
  end

  test "G7: a failed step of a blocked epic goes to another member and runs again" do
    item = @user.work_items.create!(title: "Backups", state: "blocked", started_at: 5.minutes.ago, blocked_reason: "x")
    step = item.epic_steps.create!(position: 1, title: "Research", agent: @writer, state: "failed")
    TaskRun.create!(user: @user, work_item: item, epic_step: step, agent: @writer, purpose: "epic_step", trigger: "scheduled",
                    occurrence_start: 5.minutes.ago, state: "failed", attempt: 1)
    with_claude(reply: "Daję to Kodeksowi.", actions: [ { type: "reassign_step", id: item.id, step: 1, agent: @spare_writer.id } ]) do
      chat("Daj krok 1 Kodeksowi")
    end
    run = TaskRun.where(purpose: "epic_step", state: "queued").sole
    assert_equal [ @spare_writer, @spare_writer, "planned" ], [ step.reload.agent, run.agent, item.reload.state ]
  end

  test "negative, R5: a member at its own limit, or a step not waiting, is refused" do
    item = @user.work_items.create!(title: "Backups", state: "planned", started_at: 5.minutes.ago)
    item.epic_steps.create!(position: 1, title: "Research", agent: @writer, state: "running")
    travel_to Time.zone.local(2026, 11, 22, 12, 0) do
      at_limit!(@spare, Time.zone.local(2026, 11, 22, 15, 10))
      with_claude(reply: "x", actions: [ { type: "reassign_step", id: item.id, step: 1, agent: @spare_writer.id } ]) do
        chat("Przekaż krok 1 Kodeksowi")
      end
    end
    assert_equal @writer, item.epic_steps.sole.agent
    assert_match "Not done: reassign_step: Kodeks's Claude Code usage limit reached until 15:10", @user.chat_messages.ordered.last.actions_summary # spec 047, G2
  end

  test "R4: the deputy is another agent, on another executor, and not the verifier" do
    same_executor = @user.team_roles.new(agent: @writer, role: "deputy")
    assert_not same_executor.valid?
    assert_includes same_executor.errors.full_messages.to_sentence, "runs on the director's executor"
    assert_not @user.team_roles.new(agent: @director, role: "deputy").valid?
    @user.team_roles.create!(agent: @deputy_agent, role: "deputy")
    assert_not @user.team_roles.new(agent: @spare_writer, role: "deputy").valid?, "one deputy"
    assert_not @user.team_roles.new(agent: @deputy_agent, role: "verifier").valid?
  end
end
