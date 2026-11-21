require "test_helper"

# Spec 033: the slider (G2), the epic page — Approve, answering, correcting (G1, G3, G5) — and the chat actions (G6),
# limited to the owner's own epics and messages (R4, R5).
class AutonomyPagesTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    executor = Executor.create!(name: "Claude", preset: "claude_code")
    @director = Agent.create!(user: @user, name: "Anna", master_prompt: "You direct.", executor: executor)
    @writer = Agent.create!(user: @user, name: "Pisarz", master_prompt: "You write.", executor: executor)
    @user.team_roles.create!(agent: @director, role: "director")
    @space = @user.spaces.create!(name: "Raporty", kind: "team")
    @item = @user.work_items.create!(title: "Raport", state: "blocked", space: @space, started_at: 1.minute.ago, blocked_reason: "Step 1 asks")
    @step = @item.epic_steps.create!(position: 1, title: "Research", agent: @writer, state: "waiting")
    @decision = @item.step_decisions.create!(epic_step: @step, question: "PDF czy <b>Markdown</b>?", options: [ "PDF", "Markdown" ], recommended: "Markdown",
                                             why: "Łatwiej.", important: true)
    @assumed = @item.step_decisions.create!(epic_step: @step, status: "answered", answered_by: "assumption", answer: "Odbiorca: zespół.")
    sign_in(@user)
  end

  test "G3, G5, R5: the epic page shows the question escaped with its options, hides Try again, and lists assumptions; no inline style" do
    get work_item_path(@item)
    assert_select "#decision-#{@decision.id}", text: /Step 1 asks:.*PDF czy <b>Markdown<\/b>\?/m
    assert_select "#decision-#{@decision.id} .decision-options button[title=Recommended]", text: "Markdown"
    assert_select "#decision-#{@decision.id} .decision-options button", text: "PDF"
    assert_select "#decision-#{@assumed.id}", text: /Odbiorca: zespół\..*Correct/m
    assert_select "#step-1 .badge", text: "waiting for your answer"
    assert_select "form[action='#{retry_work_item_path(@item)}']", 0
    assert_select "[style]", 0

    get notices_path, as: :json
    assert_nil response.parsed_body["blocked"].first["retry_url"], "no Try again in the pop-up either"
    post retry_work_item_path(@item)
    assert_equal "blocked", @item.reload.state
  end

  test "G3: answering with an option resumes the step; G5: correcting an assumption remembers it" do
    post answer_step_decision_path(@decision), params: { answer: "PDF" }
    assert_redirected_to work_item_path(@item)
    @item.reload
    assert_equal [ "planned", "PDF", "owner" ], [ @item.state, @decision.reload.answer, @decision.answered_by ]
    assert_equal "queued", @step.reload.state

    post correct_step_decision_path(@assumed), params: { correction: "Odbiorca: zarząd." }
    assert_equal "Odbiorca: zarząd.", @assumed.reload.correction
    assert @user.memory_facts.find_by(subject_type: "space", subject_id: @space.id, statement: "Instead of assuming \"Odbiorca: zespół.\": Odbiorca: zarząd.")
  end

  test "G1: Approve starts a plan waiting for approval" do
    planned = @user.work_items.create!(title: "Plan", state: "planned", space: @space, awaiting_approval: true)
    planned.epic_steps.create!(position: 1, title: "Do", agent: @writer)
    get work_item_path(planned)
    assert_select "#decisions", text: /The plan waits for your approval/
    post approve_work_item_path(planned)
    assert_equal [ false, "queued" ], [ planned.reload.awaiting_approval, planned.epic_steps.first.state ]
  end

  test "R4: another user's decisions and plans cannot be answered, corrected or approved" do
    other = create_user(username: "other1")
    space = other.spaces.create!(name: "X", kind: "team")
    item = other.work_items.create!(title: "Theirs", state: "planned", space: space, awaiting_approval: true)
    theirs = item.step_decisions.create!(question: "q", options: %w[a b], recommended: "a")
    post answer_step_decision_path(theirs), params: { answer: "a" }
    assert_response :not_found
    post correct_step_decision_path(theirs), params: { correction: "x" }
    assert_response :not_found
    post approve_work_item_path(item)
    assert_response :not_found
    assert [ theirs.reload.pending?, item.reload.awaiting_approval ].all?
  end

  test "G2: the slider in the chat header sets the owner's level; the space form sets the space's level" do
    get director_path
    assert_select ".chat-autonomy button", text: "Ważne pytaj"
    assert_select ".chat-autonomy button.is-active", text: "Ważne pytaj"
    patch account_autonomy_path(level: 3)
    assert_equal 3, @user.reload.autonomy_level
    patch account_autonomy_path(level: 9)
    assert_equal 3, @user.reload.autonomy_level

    patch space_path(@space), params: { space: { kind: "team", name: "Raporty", autonomy_level: "1" } }
    assert_equal 1, @space.reload.autonomy_level
    patch space_path(@space), params: { space: { kind: "team", name: "Raporty", autonomy_level: "" } }
    assert_nil @space.reload.autonomy_level
    get edit_space_path(@space)
    assert_select "select[name='space[autonomy_level]'] option", 4
  end

  # --- G6: the chat ------------------------------------------------------------------------------------

  def with_director_answer(*answers)
    Dir.mktmpdir do |bin|
      answers.each_with_index { |a, i| File.write(File.join(bin, "answer-#{i + 1}"), a.to_json) }
      File.write(File.join(bin, "claude"), "#!/bin/sh\ncat > /dev/null\nn=$(cat #{bin}/n 2>/dev/null || echo 0); n=$((n + 1)); echo $n > #{bin}/n\ncat #{bin}/answer-$n\n")
      File.chmod(0o755, File.join(bin, "claude"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      yield
    ensure
      ENV["PATH"] = original
    end
  end

  def chat(content, *answers)
    @user.chat_messages.create!(author: "user", content: content)
    with_director_answer(*answers) do
      run = ManagementRunner.chat!(@user)
      ManagementRunner.new(run.reload).perform!
    end
    @user.chat_messages.where(author: "director").order(:id).last
  end

  test "G6: the director answers a question, approves a plan and sets a level from the owner's words; it sees the question with its id" do
    actions = [ { type: "answer_decision", id: @decision.id, answer: "PDF" } ]
    reply = chat("Wybieram PDF.", { reply: "Dobrze, PDF.", actions: actions }, { reply: "ok", actions: actions })
    assert_equal [ "answered", "PDF" ], @decision.reload.values_at(:status, :answer)
    assert_match "Answered", reply.actions_summary
    prompt = TaskRun.where(purpose: "chat").order(:id).last.model_calls.first.prompt_text
    assert_match "question waiting for #{@user.username} (decision #{@decision.id}): PDF czy <b>Markdown</b>?", prompt
    assert_match "assumed: Odbiorca: zespół.", prompt

    planned = @user.work_items.create!(title: "Plan", state: "planned", space: @space, awaiting_approval: true)
    planned.epic_steps.create!(position: 1, title: "Do", agent: @writer)
    approve = [ { type: "approve_plan", id: planned.id } ]
    chat("Zatwierdzam plan.", { reply: "Startuję.", actions: approve }, { reply: "ok", actions: approve })
    assert_not planned.reload.awaiting_approval

    level = [ { type: "set_autonomy", space: @space.id, level: 3 } ]
    chat("W Raportach decyduj sam.", { reply: "Dobrze.", actions: level }, { reply: "ok", actions: level })
    assert_equal 3, @space.reload.autonomy_level
  end

  test "G6, R4: without the owner's words the director cannot approve a plan or change the level" do
    planned = @user.work_items.create!(title: "Plan", state: "planned", space: @space, awaiting_approval: true)
    actions = [ { type: "approve_plan", id: planned.id }, { type: "set_autonomy", level: 3 } ]
    chat("Co słychać w raportach?", { reply: "Wszystko gra.", actions: actions }, { reply: "ok", actions: actions })
    assert planned.reload.awaiting_approval
    assert_equal 2, @user.reload.autonomy_level
  end

  test "G6: at Decyduj the director is told not to end with questions" do
    @user.update!(autonomy_level: 3)
    chat("Jak idzie?", { reply: "Dobrze.", actions: [] })
    assert_match "do not end with questions", TaskRun.where(purpose: "chat").order(:id).last.model_calls.first.prompt_text
  end
end
