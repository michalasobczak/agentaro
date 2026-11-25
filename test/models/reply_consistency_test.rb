require "test_helper"

# Spec 050: a reply that announces what was not done is checked once, after it is posted; the missing actions the owner
# asked for are made through the usual checks, and one message says so. Replays of production cases.
class ReplyConsistencyTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @executor = Executor.create!(name: "Claude", preset: "claude_code")
    mk = ->(name) { Agent.create!(user: @user, name: name, master_prompt: "You are #{name}.", executor: @executor) }
    @director, @verifier, @worker = mk.("Dyrektor"), mk.("Sceptyk"), mk.("Inżynier")
    @user.team_roles.create!(agent: @director, role: "director")
    @user.team_roles.create!(agent: @verifier, role: "verifier")
    @user.team_roles.create!(agent: @worker, role: "member")
    @space = @user.spaces.create!(name: "Archimedev", goal: "Nadzorca")
    @answers = Dir.mktmpdir
  end

  teardown { FileUtils.rm_rf(@answers) }

  # A stand-in "claude": answers with the file named after the mode in its prompt; counts its calls per mode.
  def with_agents(answers)
    answers.each { |mode, text| File.write(File.join(@answers, mode), text.is_a?(String) ? text : text.to_json) }
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "claude"), <<~SH)
        #!/bin/sh
        input=$(cat)
        mode=$(printf '%s' "$input" | sed -n 's/^Mode: //p' | head -1)
        if printf '%s' "$input" | grep -q "You check this reply"; then mode="$mode-check"; fi
        echo x >> "#{@answers}/calls-$mode"
        printf '%s' "$input" > "#{@answers}/last-$mode-prompt"
        cat "#{@answers}/$mode"
      SH
      File.chmod(0o755, File.join(bin, "claude"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      yield
    ensure
      ENV["PATH"] = original
    end
  end

  def calls(mode) = File.exist?(f = File.join(@answers, "calls-#{mode}")) ? File.readlines(f).size : 0
  def prompt(mode) = File.read(File.join(@answers, "last-#{mode}-prompt"))

  def run_all
    10.times do
      run = TaskRun.where(state: "queued", purpose: %w[chat consistency]).order(:id).first or break
      ManagementRunner.new(run).perform!
    end
  end

  def say_user(text) = @user.chat_messages.create!(author: "user", content: text)

  def running_step_with_process
    epic = @user.work_items.create!(title: "Analiza Aut", space: @space, state: "planned", started_at: 5.minutes.ago)
    step = epic.epic_steps.create!(position: 1, title: "Pętla", agent: @worker, state: "running")
    run = TaskRun.create!(user: @user, work_item: epic, epic_step: step, agent: @worker, purpose: "epic_step", trigger: "scheduled",
                          occurrence_start: Time.current, state: "running", started_at: 2.minutes.ago)
    @pid = Process.spawn("sleep", "60", pgroup: true)
    @dir = LiveLog.dir_for(run.id)
    FileUtils.mkdir_p(@dir)
    me = ProcessTracker.snapshot.find { |p| p.pid == @pid }
    ProcessTracker.write(@dir, [ { "pid" => @pid, "started" => me.started, "command" => "sleep 60", "alive" => true, "since" => Time.current.iso8601 } ])
    run
  end

  def gone?(pid) = (Process.waitpid(pid, Process::WNOHANG); Process.kill(0, pid); false) rescue true

  test "G1: the announcement rule — first-person verbs in Polish and English, not words that only contain them" do
    assert ManagementRunner.announces?("Zatrzymuję oba jej procesy.")
    assert ManagementRunner.announces?("Zlecam więc małą poprawkę.")
    assert ManagementRunner.announces?("Usunięte, nie zapamiętam tego.")
    assert ManagementRunner.announces?("Done — I've cancelled it.")
    assert_not ManagementRunner.announces?("Zrobione.")
    assert_not ManagementRunner.announces?("Inżynier kończy wersję 0.9.0, a testy przechodzą.")
    assert_not ManagementRunner.announces?("Dyrektor dodał wcześniej zadanie.")
  end

  test "S1: replay of 973/975 — \"Zatrzymuję oba jej procesy\", nothing stopped; the check stops it and says so once" do
    run = running_step_with_process
    @user.chat_messages.create!(author: "director", content: "Krok czeka w pętli. Mogę zatrzymać ten proces.")
    say_user("tak, zatrzymaj go")
    with_agents("chat" => { reply: "Zatrzymuję oba jej procesy.", actions: [] },
                "consistency-check" => { consistent: false, missing: [ { type: "stop_process", run: run.id, pid: @pid } ],
                                         note: "Napisałem, że zatrzymuję proces, ale nic nie zostało zatrzymane — teraz zatrzymane." }) do
      ManagementRunner.chat!(@user)
      run_all
    end
    sleep 0.3
    assert gone?(@pid), "the process is stopped"
    correction = @user.chat_messages.ordered.last
    assert_equal [ "verifier", "Napisałem, że zatrzymuję proces, ale nic nie zostało zatrzymane — teraz zatrzymane." ], [ correction.author, correction.content ]
    assert_match "Stopped: sleep 60", correction.actions_summary
    assert_equal 1, calls("consistency-check"), "one check"
    assert_match "Zatrzymuję oba jej procesy.", prompt("consistency-check")
    assert_match "process of run #{run.id}, pid #{@pid}: sleep 60", prompt("consistency-check"), "G3: it sees the work list as the proposal pass does"
    assert_equal 1, TaskRun.where(purpose: "consistency").count, "G6: never a check of a check"
  ensure
    Process.kill("KILL", -@pid) rescue nil
    FileUtils.rm_rf(@dir) if @dir
  end

  test "replay of 2026-11-25 (run 1564): \"Zlecam więc małą poprawkę\", the proposal pass added nothing — the check adds the epic" do
    @user.chat_messages.create!(author: "director", content: "Przepis powstaje po skończonym zadaniu z jego całego przebiegu.")
    say_user("no to chyba przepisy też wypadałoby kategoryzować, nie tylko lekcje")
    epic = { type: "add_item", space: @space.id, title: "Kategorie dla starych przepisów", description: "Przypisać kategorie i dodać wyszukiwanie." }
    with_agents("consistency-check" => { consistent: false, missing: [ epic ], note: "Dyrektor zapowiedział zlecenie, ale zadanie nie powstało — teraz jest na liście." }) do
      chat = TaskRun.create!(user: @user, agent: @director, purpose: "chat", trigger: "scheduled", occurrence_start: Time.current, state: "running")
      runner = ManagementRunner.new(chat)
      runner.instance_variable_set(:@first_reply, "Zlecam więc małą poprawkę: model przypisze starym przepisom kategorie.")
      runner.instance_variable_set(:@first_proposed, true)
      runner.send(:apply_chat!, { "reply" => "Zlecam więc małą poprawkę: model przypisze starym przepisom kategorie.", "actions" => [] }, lenient: true, proposal: true)
      assert_equal "No changes were made to the work list or spaces.", @user.chat_messages.where(author: "director").last.actions_summary
      run_all
    end
    assert_equal [ "Kategorie dla starych przepisów" ], @user.work_items.pluck(:title)
    last = @user.chat_messages.ordered.last
    assert_equal [ "verifier", "Dyrektor zapowiedział zlecenie, ale zadanie nie powstało — teraz jest na liście." ], [ last.author, last.content ]
    assert_match "Added to the list: Kategorie dla starych przepisów", last.actions_summary
  end

  test "S2: a reply that announces an action that was applied gets no check and no call" do
    say_user("dodaj zadanie: kupić farbę")
    with_agents("chat" => { reply: "Dodaję zadanie.", actions: [ { type: "add_item", space: @space.id, title: "Kupić farbę" } ] },
                "chat-check" => "unused") do
      runner = ManagementRunner.new(TaskRun.create!(user: @user, agent: @director, purpose: "chat", trigger: "scheduled", occurrence_start: Time.current, state: "running"))
      runner.send(:apply_chat!, { "reply" => "Dodaję zadanie.", "actions" => [ { "type" => "add_item", "space" => @space.id, "title" => "Kupić farbę" } ] })
    end
    assert_equal 0, TaskRun.where(purpose: "consistency").count
    assert_equal 0, calls("consistency-check")
  end

  test "a reply that announces nothing gets no check" do
    say_user("co słychać?")
    ManagementRunner.new(TaskRun.create!(user: @user, agent: @director, purpose: "chat", trigger: "scheduled", occurrence_start: Time.current, state: "running"))
                    .send(:apply_chat!, { "reply" => "Inżynier kończy wersję 0.9.0.", "actions" => [] })
    assert_equal 0, TaskRun.where(purpose: "consistency").count
  end

  test "S3: a missing action the owner never asked for is not made, even if the checker lists it; the note says why" do
    run = running_step_with_process
    say_user("co z tą pętlą?")
    with_agents("consistency-check" => { consistent: false, missing: [ { type: "stop_process", run: run.id, pid: @pid } ],
                                         note: "Dyrektor napisał, że zatrzymuje proces, ale go nie zatrzymał; nie prosiłeś o to, więc działa dalej." }) do
      chat = TaskRun.create!(user: @user, agent: @director, purpose: "chat", trigger: "scheduled", occurrence_start: Time.current, state: "running")
      ManagementRunner.new(chat).send(:apply_chat!, { "reply" => "Zatrzymuję ten proces.", "actions" => [] })
      run_all
    end
    assert_not gone?(@pid), "nothing the owner did not ask for"
    last = @user.chat_messages.ordered.last
    assert_equal "verifier", last.author
    assert_match "has not asked in their message to stop a process", last.actions_summary
  ensure
    Process.kill("KILL", -@pid) rescue nil
    FileUtils.rm_rf(@dir) if @dir
  end

  test "S4: with a newer message of the owner, the check is skipped and no call is made" do
    say_user("dodaj zadanie: kupić farbę")
    with_agents("consistency-check" => { consistent: false, missing: [ { type: "add_item", space: @space.id, title: "Kupić farbę" } ], note: "x" }) do
      chat = TaskRun.create!(user: @user, agent: @director, purpose: "chat", trigger: "scheduled", occurrence_start: Time.current, state: "running")
      ManagementRunner.new(chat).send(:apply_chat!, { "reply" => "Dodaję zadanie.", "actions" => [] })
      say_user("a jednak nie")
      run_all
    end
    assert_equal 0, calls("consistency-check")
    assert_equal "skipped", TaskRun.find_by(purpose: "consistency").state
    assert_equal 0, @user.work_items.count
  end

  test "a consistent answer posts nothing; without a verifier the director's agent checks" do
    @user.team_roles.where(role: "verifier").destroy_all
    say_user("dodaj zadanie: kupić farbę")
    with_agents("consistency-check" => { consistent: true, missing: [], note: "" }) do
      chat = TaskRun.create!(user: @user, agent: @director, purpose: "chat", trigger: "scheduled", occurrence_start: Time.current, state: "running")
      ManagementRunner.new(chat).send(:apply_chat!, { "reply" => "Dodaję zadanie.", "actions" => [] })
      assert_equal @director, TaskRun.find_by(purpose: "consistency").agent
      assert_no_difference(-> { @user.chat_messages.count }) { run_all }
    end
    assert_equal 1, calls("consistency-check")
  end

  test "R1: a retry is never made by the check" do
    say_user("ponów krok")
    with_agents("consistency-check" => { consistent: false, missing: [ { type: "retry_step", id: 1, step: 1 } ], note: "Ponowienie nie zostało zlecone." }) do
      chat = TaskRun.create!(user: @user, agent: @director, purpose: "chat", trigger: "scheduled", occurrence_start: Time.current, state: "running")
      ManagementRunner.new(chat).send(:apply_chat!, { "reply" => "Ponawiam krok.", "actions" => [] })
      run_all
    end
    assert_match "a retry is decided with the reply", @user.chat_messages.ordered.last.actions_summary
  end
end
