require "test_helper"

# Owner fix after specs 011, 017 and 019 ("wiadomości się rozsynchronizowują … raz mówisz, że agent przyjmuje
# zadanie, a za chwilę, że nie wiesz, o co chodzi"): an answer written before the user's latest message is never
# posted as the answer to it; one director at a time; answers say which message they were written for.
class ChatOrderTest < ActiveSupport::TestCase
  # Runs a hook just before each call to the director, standing in for the user speaking while it thinks.
  class InterruptedRunner < ManagementRunner
    attr_accessor :before_call, :during_call

    private

    def call_director(...)
      before_call&.call
      super.tap { during_call&.call } # the moment the tool has answered, before the runner looks again
    end
  end

  # Stands in for the user moving on while the verifier writes its comment.
  class MovedOnRunner < ManagementRunner
    private

    def context_header
      unless @moved_on
        @moved_on = true
        @user.chat_messages.create!(author: "user", content: "Never mind, next topic")
        @user.chat_messages.create!(author: "director", content: "Sure, what next?")
      end
      super
    end
  end

  setup do
    @user = create_user
    @executor = Executor.create!(name: "Claude", preset: "claude_code")
    @director = Agent.create!(user: @user, name: "Anna", master_prompt: "You direct.", executor: @executor)
    @user.team_roles.create!(agent: @director, role: "director")
    @answers = Dir.mktmpdir
  end

  teardown { FileUtils.rm_rf(@answers) }

  # A stand-in "claude" that answers with the reply in its file and keeps every prompt it got.
  def with_director(reply)
    File.write(File.join(@answers, "reply"), { reply: reply, actions: [] }.to_json)
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "claude"), <<~SH)
        #!/bin/sh
        cat >> "#{@answers}/prompts"
        echo "=====" >> "#{@answers}/prompts"
        cat "#{@answers}/reply"
      SH
      File.chmod(0o755, File.join(bin, "claude"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      yield
    ensure
      ENV["PATH"] = original
    end
  end

  def prompts = File.read(File.join(@answers, "prompts")).split("=====\n")

  # Owner fix ("nie róbmy przerywania"): the chat holds messages while the director writes; one that still arrives
  # (another tab) does not stop the answer — it is posted, and the newer message gets the next answer.
  test "a message that arrives while the director answers: the answer is posted, not dropped; the newer one is answered next" do
    first = @user.chat_messages.create!(author: "user", content: "Add an epic: write the newsletter")
    run = ManagementRunner.chat!(@user)
    second = nil
    runner = InterruptedRunner.new(run)
    runner.before_call = -> { second ||= @user.chat_messages.create!(author: "user", content: "Actually, make it about backups") }
    with_director("Got it: a newsletter.") { runner.perform! }

    answer = @user.chat_messages.where(author: "director").sole
    assert_equal first.id, answer.reply_to_id, "it says which message it answers"
    assert_equal 1, prompts.size, "written once, not started again"
    assert TaskRun.exists?(purpose: "chat", state: "queued"), "the newer message gets the next answer"
  end

  # A message saved by another request: written straight to SQLite, so this connection's query cache is not told.
  def message_from_another_request(content)
    now = Time.current.utc.strftime("%Y-%m-%d %H:%M:%S.%6N")
    ChatMessage.connection.raw_connection.execute("INSERT INTO chat_messages (user_id, author, content, created_at, updated_at) VALUES (?, 'user', ?, ?, ?)", [ @user.id, content, now, now ])
    @user.chat_messages.where(content: content).sole
  end

  # Owner fix ("napisałem 'hi there'… zanim dokończył, napisałem 'cześć'… dwa razy podobne cześć"): background runs
  # work inside Rails' executor, where the query cache is on; the check for a newer message read the cached answer.
  test "with the query cache on, as in background runs, a message sent meanwhile is still seen and gets the next answer" do
    @user.chat_messages.create!(author: "user", content: "hi there!")
    run = ManagementRunner.chat!(@user)
    runner = InterruptedRunner.new(run)
    runner.during_call = lambda do
      runner.send(:newer_user_message?) # a check during the call fills the cache
      message_from_another_request("cześć")
    end
    with_director("Cześć!") { ActiveRecord::Base.cache { runner.perform! } }

    assert_equal 1, @user.chat_messages.where(author: "director").count
    assert TaskRun.exists?(purpose: "chat", state: "queued"), "cześć is not missed"
  end

  test "the reply being written keeps showing until it is posted, whatever the user does meanwhile" do
    @user.chat_messages.create!(author: "user", content: "Hello")
    run = ManagementRunner.chat!(@user)
    runner = ManagementRunner.new(run)
    runner.send(:see_latest_message)
    stream = runner.send(:stream_reply)
    stream.call('{"reply": "Hi the')
    @user.chat_messages.create!(author: "user", content: "Wait")
    stream.call('{"reply": "Hi there')
    assert_equal "Hi there", ReplyStream.read(run.id)
  ensure
    ReplyStream.clear(run.id) if run
  end

  # Owner fix ("jedna odpowiedź na wszystkie"): messages that waited in the chat arrive together; the director answers
  # them once, and the proposal pass reads all of them as the request.
  test "several messages that waited: one answer; the proposal pass reads all of them" do
    space = @user.spaces.create!(name: "Home", kind: "team")
    @user.chat_messages.create!(author: "director", content: "What next?")
    @user.chat_messages.create!(author: "user", content: "Add an epic")
    @user.chat_messages.create!(author: "user", content: "about backups, in Home")
    run = ManagementRunner.chat!(@user)
    File.write(File.join(@answers, "proposal"), { reply: "ok", actions: [ { type: "add_item", space: space.id, title: "Backups" } ] }.to_json)
    File.write(File.join(@answers, "reply"), { reply: "Adding Backups.", actions: [ { type: "add_item", space: space.id, title: "Backups" } ] }.to_json)
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "claude"), <<~SH)
        #!/bin/sh
        input=$(cat)
        printf '%s\\n=====\\n' "$input" >> "#{@answers}/prompts"
        if printf '%s' "$input" | grep -q '^Earlier conversation'; then cat "#{@answers}/proposal"; else cat "#{@answers}/reply"; fi
      SH
      File.chmod(0o755, File.join(bin, "claude"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      ManagementRunner.new(run).perform!
    ensure
      ENV["PATH"] = original
    end
    assert_match "Latest user message from #{@user.username}:\nAdd an epic\nabout backups, in Home", prompts.last
    assert_equal 1, @user.chat_messages.where(author: "director").where.not(content: "What next?").count
    assert @user.work_items.exists?(title: "Backups")
  end

  # Records what the chat shows while the proposal pass runs.
  class ProposalRunner < ManagementRunner
    attr_reader :shown_during_proposal

    private

    def call_director(agent, prompt, proposing_changes:)
      @shown_during_proposal = ReplyStream.read(@run.id) if proposing_changes
      super
    end
  end

  # Owner fix ("director nie wie, o czym mowa"; "wypowiedzi giną i wracają"): "q4 zajęty" answered the director's
  # questions, but the proposal pass saw only those two words and its own answer replaced the one being spoken.
  test "a short answer to the director's question: the proposal pass sees the conversation; the answer shown is kept" do
    space = @user.spaces.create!(name: "Agentaro", kind: "team")
    @user.chat_messages.create!(author: "user", content: "Where are the questions?")
    @user.chat_messages.create!(author: "director", content: "Q4: busy elsewhere or free? Shall I add an epic for it?")
    @user.chat_messages.create!(author: "user", content: "q4 busy, add it")
    run = ManagementRunner.chat!(@user)
    runner = ProposalRunner.new(run)
    File.write(File.join(@answers, "proposal"), { reply: "ok", actions: [ { type: "add_item", space: space.id, title: "Q4: busy elsewhere" } ] }.to_json)
    first = { reply: "Noted: Q4 busy elsewhere. Adding the epic.", actions: [ { type: "add_item", space: space.id, title: "Q4" } ] }.to_json
    File.write(File.join(@answers, "first"), { type: "stream_event", event: { delta: { type: "text_delta", text: first } } }.to_json + "\n")
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "claude"), <<~SH)
        #!/bin/sh
        input=$(cat)
        printf '%s\\n=====\\n' "$input" >> "#{@answers}/prompts"
        if printf '%s' "$input" | grep -q '^Earlier conversation'; then cat "#{@answers}/proposal"; exit 0; fi
        cat "#{@answers}/first"
      SH
      File.chmod(0o755, File.join(bin, "claude"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      runner.perform!
    ensure
      ENV["PATH"] = original
    end

    proposal = prompts.last
    assert_match "Director: Q4: busy elsewhere or free?", proposal, "the proposal pass knows what q4 refers to"
    assert_match "#{@user.username}: Where are the questions?", proposal
    assert_match "Latest user message from #{@user.username}:\nq4 busy, add it", proposal
    answer = @user.chat_messages.where(author: "director").last
    assert_match "Noted: Q4 busy elsewhere", answer.content, "the answer written with the whole conversation is posted"
    assert_match "Q4: busy elsewhere", answer.actions_summary, "what was really applied is noted under it"
    assert @user.work_items.exists?(title: "Q4: busy elsewhere")
    assert_equal "Noted: Q4 busy elsewhere. Adding the epic.", runner.shown_during_proposal, "the answer being spoken does not vanish meanwhile"
  end

  test "one director at a time, even when two messages arrive at the same moment" do
    @user.chat_messages.create!(author: "user", content: "One")
    runs = Array.new(4) { Thread.new { ManagementRunner.chat!(@user) } }.map(&:value)
    assert_equal 1, runs.compact.size
    assert_equal 1, TaskRun.where(purpose: "chat").count
  end

  test "the verifier's comment on an answer the user has moved on from is not posted; the newer answer is checked" do
    verifier = Agent.create!(user: @user, name: "Wera", master_prompt: "You check.", executor: Executor.create!(name: "Codex", preset: "codex"))
    @user.team_roles.create!(agent: verifier, role: "verifier")
    @user.update!(verifier_active: true)
    @user.chat_messages.create!(author: "user", content: "Is it done?")
    @user.chat_messages.create!(author: "director", content: "Yes.")
    run = ManagementRunner.verify!(@user)
    runner = MovedOnRunner.new(run)
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "codex"), <<~SH)
        #!/bin/sh
        cat > /dev/null
        out=""; prev=""
        for a in "$@"; do if [ "$prev" = "-o" ]; then out="$a"; fi; prev="$a"; done
        printf 'Not verified.' > "$out"
      SH
      File.chmod(0o755, File.join(bin, "codex"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      runner.perform!
    ensure
      ENV["PATH"] = original
    end
    assert_not @user.chat_messages.exists?(author: "verifier"), "an outdated comment is not posted"
    assert TaskRun.where(purpose: "verify", state: "queued").exists?, "the director's newer answer is checked"
  end
end
