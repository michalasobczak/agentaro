require "test_helper"

# Owner fix after specs 011, 017 and 019 ("wiadomości się rozsynchronizowują … raz mówisz, że agent przyjmuje
# zadanie, a za chwilę, że nie wiesz, o co chodzi"): an answer written before the user's latest message is never
# posted as the answer to it; one director at a time; answers say which message they were written for.
class ChatOrderTest < ActiveSupport::TestCase
  # Runs a hook just before each call to the director, standing in for the user speaking while it thinks.
  class InterruptedRunner < ManagementRunner
    attr_accessor :before_call

    private

    def call_director(...)
      before_call&.call
      super
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

  test "a message written while the director answers: the outdated answer is not posted; one answer to everything" do
    first = @user.chat_messages.create!(author: "user", content: "Add an epic: write the newsletter")
    run = ManagementRunner.chat!(@user)
    second = nil
    runner = InterruptedRunner.new(run)
    runner.before_call = -> { second ||= @user.chat_messages.create!(author: "user", content: "Actually, make it about backups") }
    with_director("Got it: a newsletter about backups.") { runner.perform! }

    answers = @user.chat_messages.where(author: "director").to_a
    assert_equal 1, answers.size, "the answer written before the second message is dropped"
    assert_equal second.id, answers.sole.reply_to_id
    assert_operator answers.sole.id, :>, second.id
    assert_equal 2, prompts.size, "the director answered again"
    assert_no_match "make it about backups", prompts.first
    assert_match "make it about backups", prompts.last
    assert_match first.content, prompts.last
    assert_equal 0, TaskRun.where(purpose: "chat", state: %w[queued running]).count, "nothing left to answer"
  end

  test "a user who keeps talking: after a few fresh starts the answer is posted, marked, and the newest message gets its own" do
    @user.chat_messages.create!(author: "user", content: "One")
    run = ManagementRunner.chat!(@user)
    runner = InterruptedRunner.new(run)
    count = 0
    runner.before_call = -> { @user.chat_messages.create!(author: "user", content: "More #{count += 1}") }
    with_director("Answer") { runner.perform! }

    assert_equal ManagementRunner::MAX_FRESH_STARTS + 1, prompts.size
    answer = @user.chat_messages.where(author: "director").sole
    assert_operator answer.reply_to_id, :<, @user.chat_messages.where(author: "user").maximum(:id), "it says it answers an earlier message"
    assert TaskRun.exists?(purpose: "chat", state: "queued"), "the newest message is answered next"
  end

  test "a reply being written is no longer shown or spoken once the user writes again" do
    @user.chat_messages.create!(author: "user", content: "Hello")
    run = ManagementRunner.chat!(@user)
    runner = ManagementRunner.new(run)
    runner.send(:see_latest_message)
    stream = runner.send(:stream_reply)
    stream.call('{"reply": "Hi the')
    assert_equal [ "Hi the", @user.chat_messages.last.id ], [ ReplyStream.read(run.id), ReplyStream.reply_to(run.id) ]
    @user.chat_messages.create!(author: "user", content: "Wait")
    sleep 1.05 # the stream checks at most once a second
    stream.call('{"reply": "Hi there')
    assert_nil ReplyStream.read(run.id)
  ensure
    ReplyStream.clear(run.id) if run
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
