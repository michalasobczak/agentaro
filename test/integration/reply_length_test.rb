require "test_helper"

# Spec 039: how much the director writes — Krótko by default (S1), the switch in both chats (G2, S2), the rule only
# in the text reply (R2, R3), the chat action only on the owner's words (G3, R4, S3).
class ReplyLengthTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    executor = Executor.create!(name: "Claude", preset: "claude_code")
    @director = Agent.create!(user: @user, name: "Anna", master_prompt: "You direct.", executor: executor)
    @user.team_roles.create!(agent: @director, role: "director")
    sign_in(@user)
  end

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

  def chat(content, *answers, spoken: false)
    @user.chat_messages.create!(author: "user", content: content, spoken: spoken)
    with_director_answer(*answers) do
      run = ManagementRunner.chat!(@user)
      ManagementRunner.new(run.reload).perform!
    end
    @user.chat_messages.where(author: "director").order(:id).last
  end

  def prompts = TaskRun.where(purpose: "chat").order(:id).last.model_calls.order(:position).map(&:prompt_text)

  test "S1, R2: Krótko by default; the rule is in the reply's prompt, not in the proposal pass" do
    assert_equal 1, @user.reply_length
    assert_equal 1, User.new.reply_length
    chat("Co słychać?", { reply: "Dobrze.", actions: [] }, { reply: "ok", actions: [] })
    reply, proposal = prompts
    assert_match "Reply length chosen by #{@user.username}: Krótko — at most 3 sentences", reply
    assert_no_match "Reply length chosen", proposal.to_s
  end

  test "G2, S2: the switch in both chats sets the level and marks it; an unknown level is refused; no inline style" do
    get director_path
    assert_select ".content .chat-length button", count: 3
    assert_select ".chat-dock .chat-length button", count: 3
    assert_select ".content .chat-length button.is-active[aria-pressed=true]", text: "Krótko"
    assert_select "[style]", 0

    patch account_reply_length_path(level: 2)
    assert_equal 2, @user.reload.reply_length
    patch account_reply_length_path(level: 7)
    assert_equal 2, @user.reload.reply_length
    get director_path
    assert_select ".content .chat-length button.is-active", text: "Średnio"
    chat("Jak idzie?", { reply: "Dobrze.", actions: [] }, { reply: "ok", actions: [] })
    assert_match "Reply length chosen by #{@user.username}: Średnio — one short paragraph", prompts.first
  end

  test "R3, S4: in voice mode the spoken rule stands instead" do
    chat("Co słychać?", { reply: "Dobrze.", actions: [] }, { reply: "ok", actions: [] }, spoken: true)
    assert_no_match "Reply length chosen", prompts.first
    assert_match "hears your reply read aloud", prompts.first
  end

  test "G3, S3: \"pisz krócej\" changes the level and says so; without such words the director cannot" do
    @user.update!(reply_length: 3)
    action = [ { type: "set_reply_length", level: 1 } ]
    reply = chat("Pisz krócej, proszę.", { reply: "Dobrze.", actions: action }, { reply: "ok", actions: action })
    assert_equal 1, @user.reload.reply_length
    assert_match "Reply length: Krótko", reply.actions_summary

    action = [ { type: "set_reply_length", level: 3 } ]
    chat("Co z backupami?", { reply: "Wszystko gra.", actions: action }, { reply: "ok", actions: action })
    assert_equal 1, @user.reload.reply_length, "R4: no change without the owner's words"
  end
end
