require "test_helper"

# Spec 046: the Rozmowa switch (G1), the director's conversational rule (G2, S1), the voice (G3, S2) and what is read
# aloud (G5, S4: system lines and "applied" notes never reach the voice — checked in chat.js, unchanged by this spec).
class ConversationModeTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    executor = Executor.create!(name: "Claude", preset: "claude_code")
    @director = Agent.create!(user: @user, name: "Anna", master_prompt: "You direct.", executor: executor)
    @user.team_roles.create!(agent: @director, role: "director")
    sign_in(@user)
  end

  def chat(content, *answers)
    @user.chat_messages.create!(author: "user", content: content)
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
    @user.chat_messages.where(author: "director").order(:id).last
  end

  def first_prompt = TaskRun.where(purpose: "chat").order(:id).last.model_calls.order(:position).first.prompt_text

  test "G1: Naturalna is the default; the switch in the panel saves Zwykła and back" do
    assert_equal 2, @user.conversation_mode
    get director_path
    assert_select ".chat-settings-panel .chat-conversation button", text: "Naturalna", count: 2 # page and dock
    assert_select ".chat-app[data-conversation=natural][data-acknowledgements='Już sprawdzam.|Chwilka.|Moment, patrzę.']"
    patch account_conversation_mode_path(level: 1)
    assert_equal 1, @user.reload.conversation_mode
    get director_path
    assert_select ".chat-app[data-conversation=plain]"
    patch account_conversation_mode_path(level: 7)
    assert_equal 1, @user.reload.conversation_mode, "an unknown level changes nothing"
  end

  test "S1, G2: the conversational rule is in the director's prompt with Naturalna, beside the style, and not with Zwykła" do
    chat("Co słychać?", { reply: "Dobrze.", actions: [] })
    assert_match "Conversation mode chosen by alice: Naturalna", first_prompt
    assert_match "Conversation style chosen by alice", first_prompt
    @user.update!(conversation_mode: 1)
    chat("A teraz?", { reply: "Też.", actions: [] })
    assert_no_match(/Conversation mode chosen/, first_prompt)
  end

  test "G1: the owner's words switch the mode; without them the director cannot" do
    action = [ { type: "set_conversation", level: 1 } ]
    reply = chat("Rozmawiaj zwykle, bez tej naturalności.", { reply: "Dobrze.", actions: action }, { reply: "ok", actions: action })
    assert_equal 1, @user.reload.conversation_mode
    assert_match "Conversation: Zwykła", reply.actions_summary
    back = [ { type: "set_conversation", level: 2 } ]
    chat("Co u ciebie?", { reply: "Zmieniam.", actions: back }, { reply: "Zmieniam.", actions: back }, { reply: "Nic.", actions: [] })
    assert_equal 1, @user.reload.conversation_mode, "no words about the conversation, no change"
  end
end
