require "test_helper"

# Spec 041: the settings panel in both chats (G1, S1, S2, R8), the compact voice bar (G2), the style in the director's
# prompt, written and spoken (G3, R2, S4), the tempo select on the space form (G5) and the chat actions (G6, R7, S8).
class StyleAndTempoTest < ActionDispatch::IntegrationTest
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

  test "G1, S1, R8: one settings icon in both chats; every switch is in its panel; no switch outside it; no inline style" do
    get director_path
    [ ".content .chat-app", ".chat-dock .chat-app.is-dock" ].each do |app|
      assert_select "#{app} .chat-head > details.chat-settings[data-chat-settings]", 1 do
        assert_select "summary.chat-tool[aria-label='Chat settings'] svg.icon", 1
        assert_select ".chat-settings-panel .chat-setting-label", text: /\A(Language|Autonomy|Reply length|Style|Tempo|Background)\z/, count: 6
        assert_select ".chat-settings-panel .lang-switch", 5
        assert_select ".chat-settings-panel .lang-switch[aria-label='Conversation language']", 1
        %w[chat-autonomy chat-length chat-style chat-tempo].each { |css| assert_select ".chat-settings-panel .#{css}", 1 }
        assert_select ".chat-settings-panel form.chat-bg", 1
      end
      assert_select "#{app} .chat-head > .lang-switch, #{app} .chat-head > form.chat-bg", 0, "no switch outside the panel"
    end
    assert_select ".content .chat-style button.is-active[aria-pressed=true]", text: "Dorosły"
    assert_select ".content .chat-tempo button.is-active[aria-pressed=true]", text: "Normalnie"
    assert_select "[style]", 0
    assert_select "script:not([src])", 0
  end

  test "S2: the switches save the style and the tempo and mark them; unknown values are refused" do
    patch account_chat_style_path(level: 1)
    patch account_work_tempo_path(level: 3)
    assert_equal [ 1, 3 ], [ @user.reload.chat_style, @user.work_tempo ]
    patch account_chat_style_path(level: 4)
    patch account_work_tempo_path(level: "x")
    assert_equal [ 1, 3 ], [ @user.reload.chat_style, @user.work_tempo ]
    get director_path
    assert_select ".content .chat-style button.is-active", text: "Dziecko"
    assert_select ".content .chat-tempo button.is-active", text: "Turbo"
  end

  test "G2: the voice bar is icons — Mute and Done without visible labels, the speed as one button" do
    get director_path
    assert_select ".content [data-voice-panel]" do
      assert_select "[data-voice-mute] .voice-mute-label.visually-hidden", 1
      assert_select "[data-voice-done][aria-label]", 1
      assert_select "[data-voice-done]", text: ""
      assert_select ".speed-switch", 0
      assert_select "button.voice-speed[data-speed-url][data-speeds][title]", 1
    end
  end

  test "S4, R2: the Dorosły rule in the reply prompt, written and spoken; not in the proposal pass" do
    chat("Co słychać?", { reply: "Dobrze.", actions: [] }, { reply: "ok", actions: [] })
    reply, proposal = prompts
    assert_match "Conversation style chosen by #{@user.username}: Dorosły", reply
    assert_no_match "Conversation style chosen", proposal.to_s
    @user.update!(chat_style: 3)
    chat("A teraz?", { reply: "Dobrze.", actions: [] }, { reply: "ok", actions: [] }, spoken: true)
    assert_match "Conversation style chosen by #{@user.username}: Inżynier", prompts.first
    assert_match "hears your reply read aloud", prompts.first
  end

  test "G6, S8: the owner's words change the style and the tempo (also a space's); without them the director cannot" do
    space = @user.spaces.create!(name: "Kod", kind: "team")
    actions = [ { type: "set_style", level: 1 }, { type: "set_tempo", level: 3 }, { type: "set_tempo", space: space.id, level: 1 } ]
    reply = chat("Mów do mnie jak do dziecka i rób wszystko w turbo, a w Kodzie dokładnie.", { reply: "Dobrze.", actions: actions }, { reply: "ok", actions: actions })
    assert_equal [ 1, 3, 1 ], [ @user.reload.chat_style, @user.work_tempo, space.reload.work_tempo ]
    assert_match "Style: Dziecko", reply.actions_summary
    assert_match "Tempo: Turbo", reply.actions_summary
    assert_match "Tempo of Kod: Dokładnie", reply.actions_summary

    others = [ { type: "set_style", level: 3 }, { type: "set_tempo", level: 2 } ]
    chat("Co u ciebie?", { reply: "Zmieniam.", actions: others }, { reply: "Zmieniam.", actions: others }, { reply: "Nic.", actions: [] })
    assert_equal [ 1, 3 ], [ @user.reload.chat_style, @user.work_tempo ], "R7: no words about style or tempo, no change"
  end

  test "G5: the space form saves its own tempo; empty means the owner's default" do
    space = @user.spaces.create!(name: "Kod", kind: "team")
    get edit_space_path(space)
    assert_select "select[name='space[work_tempo]'] option[value='']", text: "Your default (Normalnie)"
    patch space_path(space), params: { space: { work_tempo: "3" } }
    assert_equal 3, space.reload.work_tempo
    patch space_path(space), params: { space: { work_tempo: "" } }
    assert_nil space.reload.work_tempo
    patch space_path(space), params: { space: { work_tempo: "8" } }
    assert_nil space.reload.work_tempo, "an invalid tempo is not saved"
  end
end
