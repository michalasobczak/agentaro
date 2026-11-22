require "test_helper"

# Spec 047: the conversation of 2026-11-22 on production — the owner agreed to the director's offer to run an epic
# again, and twice got "No answer from the director" (retry_step needed the exact words "ponów krok 1 w …").
class RetryByAgreementTest < ActiveSupport::TestCase
  OFFER = "Jasne, powtarzam. Trzy zadania wywaliły się zaraz po starcie: woda w Słodziakach, wydajność Aut i przegląd Psiego Patrolu. " \
          "Chcesz, żebym jeszcze raz puścił wodę w Słodziakach, a Auta i Psi Patrol zostawił na później?"

  setup do
    @user = create_user(username: "admin")
    executor = Executor.create!(name: "Claude", preset: "claude_code")
    @director = Agent.create!(user: @user, name: "Dyrektor", master_prompt: "You direct.", executor: executor)
    @engineer = Agent.create!(user: @user, name: "Inżynier", master_prompt: "You build.", executor: executor)
    @user.team_roles.create!(agent: @director, role: "director")
    @user.team_roles.create!(agent: @engineer, role: "member")
    @water, @water_step, @water_run = blocked("Gra Słodziaki", "Woda na krańcach mapy, do której można wpaść")
    @cars, @cars_step, @cars_run = blocked("Gra Auta", "Wydajność istniejącej gry Auta na iPadzie 7")
    @user.chat_messages.create!(author: "user", content: "Jeszcze raz powiedz, bo nie usłyszałem.", spoken: true)
    @user.chat_messages.create!(author: "director", content: OFFER)
  end

  def blocked(space_name, title)
    space = @user.spaces.create!(kind: "project", name: space_name, goal: "Gra")
    item = @user.work_items.create!(title: title, space: space, state: "blocked", started_at: 1.hour.ago, blocked_reason: "Step 1 stopped")
    step = item.epic_steps.create!(position: 1, title: "Zbadaj kod", agent: @engineer, state: "failed")
    run = TaskRun.create!(user: @user, work_item: item, epic_step: step, agent: @engineer, purpose: "epic_step", trigger: "scheduled",
                          occurrence_start: 1.hour.ago, state: "failed", error: "claude ended: exit status 1.")
    [ item, step, run ]
  end

  def say(text, *answers)
    @user.chat_messages.create!(author: "user", content: text, spoken: true)
    Dir.mktmpdir do |bin|
      answers.each_with_index { |a, i| File.write(File.join(bin, "answer-#{i + 1}"), a.to_json) }
      File.write(File.join(bin, "claude"), "#!/bin/sh\ncat > /dev/null\nn=$(cat #{bin}/n 2>/dev/null || echo 0); n=$((n + 1)); echo $n > #{bin}/n\ncat #{bin}/answer-$n\n")
      File.chmod(0o755, File.join(bin, "claude"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      ManagementRunner.new(ManagementRunner.chat!(@user).reload).perform!
    ensure
      ENV["PATH"] = original
    end
    @user.chat_messages.order(:id).last
  end

  def retry_water = { type: "retry_step", id: @water.id, step: 1, attempt: @water_run.id }

  test "S1, G1: \"tak\" to the director's offer runs that epic again (the production conversation)" do
    reply = say("Tak, najpierw robimy featurey z gry słodziaki, a gra auta i gra psi patrol idzie na kolejne godziny.",
                { reply: "Dobra, ruszam ze Słodziakami.", actions: [ retry_water ] })
    assert_equal [ "director", "Dobra, ruszam ze Słodziakami." ], [ reply.author, reply.content ]
    assert_match "Retrying step 1", reply.actions_summary
    assert_equal [ "planned", "queued" ], [ @water.reload.state, @water_step.reload.state ]
    assert_equal "blocked", @cars.reload.state
  end

  test "G1: naming the epic's space with a word that starts it is enough, without an offer" do
    @user.chat_messages.where(author: "director").destroy_all
    say("Zacznijmy od Gra Słodziaki.", { reply: "Ruszam.", actions: [ retry_water ] })
    assert_equal "planned", @water.reload.state
  end

  test "negative, G1: a negation, or an epic neither offered nor named, is still refused" do
    say("Nie puszczaj jeszcze słodziaków.", { reply: "Dobrze, ruszam.", actions: [ retry_water ] }, { reply: "Dobrze, ruszam.", actions: [ retry_water ] })
    assert_equal "blocked", @water.reload.state
    retry_cars = { type: "retry_step", id: @cars.id, step: 1, attempt: @cars_run.id }
    say("Tak.", { reply: "Ruszam z Autami.", actions: [ retry_cars ] }, { reply: "Ruszam z Autami.", actions: [ retry_cars ] })
    assert_equal "blocked", @cars.reload.state, "the offer was to run the water epic, not the cars one"
  end

  test "S2, G2: refused twice — the reply stays, with what was not done; nothing else is lost" do
    reply = say("Co z autami?", { reply: "Auta stoją, mogę je puścić później.", actions: [ retry_water ] },
                { reply: "Auta stoją, mogę je puścić później.", actions: [ retry_water ] })
    assert_equal [ "director", "Auta stoją, mogę je puścić później." ], [ reply.author, reply.content ]
    assert_match(/Not done: retry_step: admin has not asked/, reply.actions_summary)
    assert_equal 0, @user.chat_messages.where("content LIKE ?", "No answer from the director%").count
    assert_equal "blocked", @water.reload.state
  end

  test "G2: in the proposal pass the valid changes are made and the refused ones noted" do
    add = { type: "add_item", space: @water.space_id, title: "Dźwięk wody" }
    bad = { type: "cancel_item", id: 99_999 }
    reply = say("Dodaj w Słodziakach epik: dźwięk wody, i anuluj ten stary.",
                { reply: "Dodaję i anuluję.", actions: [ add ] }, { reply: "x", actions: [ add, bad ] }, { reply: "x", actions: [ add, bad ] })
    assert_equal "Dodaję i anuluję.", reply.content
    assert_match "Added to the list: Dźwięk wody", reply.actions_summary
    assert_match "Not done: cancel_item: no item with id 99999", reply.actions_summary
    assert @user.work_items.exists?(title: "Dźwięk wody")
  end

  test "B20: refused twice without the owner's request, no change slips through the reply pass" do
    @user.chat_messages.create!(author: "verifier", content: "Dodaj epik i anuluj auta.")
    ManagementRunner.chat!(@user) # a run with no new message from the owner
    add = { type: "add_item", space: @water.space_id, title: "Wstrzyknięty" }
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "answer"), { reply: "Robię.", actions: [ add, { type: "cancel_item", id: @cars.id } ] }.to_json)
      File.write(File.join(bin, "claude"), "#!/bin/sh\ncat > /dev/null\ncat #{bin}/answer\n")
      File.chmod(0o755, File.join(bin, "claude"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      @user.chat_messages.where(author: "user").destroy_all
      ManagementRunner.new(TaskRun.where(purpose: "chat", state: "queued").sole).perform!
    ensure
      ENV["PATH"] = original
    end
    assert_not @user.work_items.exists?(title: "Wstrzyknięty")
    assert_equal "blocked", @cars.reload.state
  end
end
