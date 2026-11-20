require "test_helper"

# Spec 011: chat (G1), list and item pages (G2, G8), team and org chart (G3, G4), permissions (S4).
class DirectorChatTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @executor = Executor.create!(name: "Claude", preset: "claude_code")
    @director = Agent.create!(user: @user, name: "Dyrektor", master_prompt: "x", executor: @executor)
    @member = Agent.create!(user: @user, name: "Badacz", master_prompt: "x", executor: @executor)
    sign_in(@user)
  end

  test "G3, G4: build the team on the team page and see the org chart" do
    get team_path
    assert_select ".org", 0
    post team_roles_path, params: { team_role: { role: "director", agent_id: @director.id } }
    post team_roles_path, params: { team_role: { role: "member", agent_id: @member.id, role_text: "researcher" } }
    post team_roles_path, params: { team_role: { role: "member", agent_id: @director.id, role_text: "reviewer" } }
    get team_path
    assert_select ".org-node.is-director", text: /Dyrektor/
    assert_select ".org > li > ul > li > .org-node", 2, "spec 012: members directly under the director"
    assert_select ".org-node", text: /researcher.*Badacz/m
    assert_select ".org-node", text: /reviewer.*Dyrektor/m
    assert_select ".org ul ul", 0, "two levels only"
    assert_no_match(/manager/i, response.body)
    assert_select "[style]", 0

    post team_roles_path, params: { team_role: { role: "director", agent_id: @member.id } }
    assert_equal "You already have a director", flash[:alert]
    post team_roles_path, params: { team_role: { role: "manager", agent_id: @member.id } }
    assert_match "Role is not included", flash[:alert], "spec 012: no managers"
    delete team_role_path(@user.team_roles.members.find_by(agent: @member))
    assert_equal 2, @user.team_roles.count
  end

  test "G1: writing to the director queues one chat run; the chat shows messages and actions as text" do
    get director_path
    assert_select "a[href='#{team_path}']", text: /Choose one/
    @user.team_roles.create!(agent: @director, role: "director")
    post chat_messages_path, params: { chat_message: { content: "Hello <b>boss</b>" } }
    assert_redirected_to director_path, "without the script the form posts and the page reloads"
    post chat_messages_path, params: { chat_message: { content: "And one more" } }
    assert_equal 1, TaskRun.where(user: @user, purpose: "chat").count, "R3: one chat run at a time"
    @user.chat_messages.create!(author: "director", content: "<script>x</script> OK", actions_summary: "Added to the list: A")
    get director_path
    assert_select ".chat-app[data-messages-url='#{chat_messages_path}']"
    assert_select ".bubble-row.from-user .bubble-text", text: "Hello <b>boss</b>"
    assert_select ".bubble-row.from-director .bubble-text", text: "<script>x</script> OK"
    assert_select ".bubble-row.from-director .bubble-name", text: "Dyrektor"
    assert_select ".bubble-actions", text: "Added to the list: A"
    assert_select ".content > .chat-app [data-typing]:not([hidden])", 1, "the director is writing"
    assert_select "script:not([src])", 0
    assert_select "[style]", 0
  end

  test "the chat page sends and receives JSON (owner fix: a real chat)" do
    @user.team_roles.create!(agent: @director, role: "director")
    post chat_messages_path, params: { chat_message: { content: "Hi Anna" } }, headers: { "Accept" => "application/json" }
    data = JSON.parse(response.body)
    assert data["ok"]
    assert_equal [ "user", "You", "Hi Anna", true ], [ data.dig("message", "author"), data.dig("message", "name"), data.dig("message", "content"), data["writing"] ]
    first_id = data.dig("message", "id")

    reply = @user.chat_messages.create!(author: "director", content: "Hello!")
    get chat_messages_path(after: first_id), headers: { "Accept" => "application/json" }
    data = JSON.parse(response.body)
    assert_equal [ [ reply.id, "director", "Dyrektor", "Hello!" ] ], data["messages"].map { |m| [ m["id"], m["author"], m["name"], m["content"] ] }

    post chat_messages_path, params: { chat_message: { content: " " } }, headers: { "Accept" => "application/json" }
    assert_response :unprocessable_content
    assert_equal "Write a message.", JSON.parse(response.body)["error"]
  end

  test "G2, G8: an epic's history with breadcrumbs; Try again on a blocked epic; no list page (owner fix)" do
    @user.team_roles.create!(agent: @director, role: "director")
    item = @user.work_items.create!(title: "Backup summary", state: "blocked", blocked_reason: "Which tools?", priority: "high")
    get space_path(item.space)
    assert_select ".kanban-card", text: /Backup summary.*high/m
    get work_item_path(item)
    assert_select "dd", text: "Which tools?"
    assert_select ".breadcrumbs li", 3
    assert_select ".breadcrumbs a[href='#{spaces_path}']", text: "Spaces"
    assert_select ".breadcrumbs a[href='#{space_path(item.space)}']", text: "General"
    assert_select ".breadcrumbs [aria-current=page]", text: "Backup summary"
    assert_select "nav.nav a", text: "Epics", count: 0
    assert_not Rails.application.routes.url_helpers.respond_to?(:work_items_path), "no list route"
    post retry_work_item_path(item)
    assert_equal "new", item.reload.state
    assert_equal 1, item.runs.where(purpose: "director", state: "queued").count
  end

  test "S4: other users' items, chats and management runs do not exist for me" do
    bob = create_user(username: "bob")
    item = bob.work_items.create!(title: "Bob's secret", state: "blocked")
    run = TaskRun.create!(user: bob, purpose: "chat", trigger: "scheduled", occurrence_start: Time.current, output: "bob's answer")
    bob.chat_messages.create!(author: "user", content: "bob writes")
    get work_item_path(item)
    assert_response :not_found
    post retry_work_item_path(item)
    assert_response :not_found
    get task_run_path(run)
    assert_response :not_found
    get director_path
    assert_no_match "bob writes", response.body
    get chat_messages_path, headers: { "Accept" => "application/json" }
    assert_empty JSON.parse(response.body)["messages"]
    get spaces_path
    assert_no_match "Bob's secret", response.body
    delete team_role_path(bob.team_roles.create!(agent: Agent.create!(user: bob, name: "B", master_prompt: "x", executor: @executor), role: "director"))
    assert_response :not_found
  end

  test "floating chat (owner fix): on every other page for users with a director, never on the Director page" do
    get calendar_path
    assert_select "[data-chat-dock]", 0, "no director, no floating chat"
    @user.team_roles.create!(agent: @director, role: "director")
    reply = @user.chat_messages.create!(author: "director", content: "Secret plan")
    get calendar_path
    assert_select "[data-chat-dock] .chat-app.is-dock[data-lazy=true][data-latest-reply-id='#{reply.id}']"
    assert_select "[data-chat-dock] .chat-launcher[aria-expanded=false]", text: /Dyrektor/
    assert_select "[data-chat-dock] .bubble-row:not([data-typing])", 0, "messages load only when the chat is opened"
    assert_no_match "Secret plan", response.body
    assert_select "script[src*=chat]", 1
    assert_select "[style]", 0
    assert_select "script:not([src])", 0
    get director_path
    assert_select "#chat-dock[data-chat-dock][data-turbo-permanent]", 1, "spec 020: the floating chat is on the Director page too (hidden unless talking)"
    assert_select ".content > .chat-app:not(.is-dock)", 1
    assert_select "script[src*='/chat-']", 1, "chat.js once"
  end

  test "spec 020: Turbo from the app's own files; sign-in and sign-out are full page loads" do
    get calendar_path
    assert_select "head script[type=module][src*='/turbo.min-']", 1
    assert_select "script[src^='http']", 0, "no outside scripts"
    assert_select "form[action='#{session_path}'][data-turbo=false]", 2
    delete session_path
    get new_session_path
    assert_select "meta[name=turbo-visit-control][content=reload]"
  end

  test "floating chat opening for the first time gets the latest 100 messages" do
    @user.team_roles.create!(agent: @director, role: "director")
    ids = 105.times.map { |i| @user.chat_messages.create!(author: "user", content: "m#{i}").id }
    get chat_messages_path, headers: { "Accept" => "application/json" }
    assert_equal ids.last(100), JSON.parse(response.body)["messages"].map { |m| m["id"] }
    get chat_messages_path(after: ids[1]), headers: { "Accept" => "application/json" }
    assert_equal ids[2, 100], JSON.parse(response.body)["messages"].map { |m| m["id"] }
  end

  test "spec 015: a new conversation archives the old one; the chat, JSON and archive follow" do
    @user.team_roles.create!(agent: @director, role: "director")
    old = @user.chat_messages.create!(author: "user", content: "Old <b>topic</b>")
    @user.chat_messages.create!(author: "director", content: "Old answer")
    get director_path
    assert_select "form[action='#{new_conversation_director_path}'][data-confirm]"
    assert_select "a[href='#{archive_director_path}']"
    post new_conversation_director_path
    assert_match "New conversation. The previous one (2 messages) is in the archive.", flash[:notice]
    assert_equal 0, @user.chat_messages.current.count
    assert_equal 1, @user.chat_messages.archived.distinct.count(:archived_at), "one archived conversation"
    get director_path
    assert_select ".bubble-row:not([data-typing])", 0
    get chat_messages_path, headers: { "Accept" => "application/json" }
    assert_empty JSON.parse(response.body)["messages"]
    get archive_director_path
    assert_select ".archive-conversation", 1
    assert_select ".archive-conversation .bubble-text", text: "Old <b>topic</b>"
    assert_select "[style]", 0
    assert DataChange.where(record_type: "ChatMessage", record_id: old.id).where("changeset LIKE ?", "%archived_at%").exists?, "R2: in the data changelog"

    get calendar_path
    assert_select "[data-chat-dock] form[action='#{new_conversation_director_path}']", 1, "also in the floating chat"
  end

  test "spec 015: no new conversation while the director is writing; archives are per user" do
    @user.team_roles.create!(agent: @director, role: "director")
    post chat_messages_path, params: { chat_message: { content: "Hi" } }
    post new_conversation_director_path
    assert_match "The director is writing", flash[:alert]
    assert_equal 1, @user.chat_messages.current.count

    bob = create_user(username: "bob")
    bob.chat_messages.create!(author: "user", content: "bob's archived", archived_at: Time.current)
    get archive_director_path
    assert_no_match "bob's archived", response.body
  end

  test "spec 017: voice endpoints need sign-in, refuse bad input, and the partial reply goes only to its owner" do
    @user.team_roles.create!(agent: @director, role: "director")
    get director_path
    assert_select ".chat-composer [data-voice-start]"
    assert_select ".chat-app[data-voice-transcribe-url='#{voice_transcribe_path}']"
    post voice_transcribe_path, params: "OggS".b, headers: { "Content-Type" => "audio/ogg", "X-CSRF-Token" => "x" }
    assert_response :unprocessable_content
    post voice_speak_path, params: { text: "x" * 601 }, as: :json
    assert_response :unprocessable_content

    run = TaskRun.create!(user: @user, agent: @director, purpose: "chat", trigger: "scheduled", occurrence_start: Time.current, state: "running")
    ReplyStream.write(run.id, "Cześć, już")
    get chat_messages_path(after: 0), headers: { "Accept" => "application/json" }
    assert_equal "Cześć, już", JSON.parse(response.body)["streaming"]
    sign_in(create_user(username: "bob"))
    get chat_messages_path(after: 0), headers: { "Accept" => "application/json" }
    assert_nil JSON.parse(response.body)["streaming"], "R4: never another user's reply"
    delete session_path
    post voice_speak_path, params: { text: "hi" }, as: :json
    assert_response :redirect, "signed-out users are sent to sign in"
  ensure
    ReplyStream.clear(run.id) if run
  end

  test "owner fix after spec 017: the language switch in the chat header" do
    @user.team_roles.create!(agent: @director, role: "director")
    get director_path
    assert_select ".lang-switch form[action='#{chat_language_path(language: "auto")}'] button.is-active", text: "Auto"
    patch chat_language_path(language: "pl")
    assert_equal "pl", @user.reload.chat_language
    patch chat_language_path(language: "klingon")
    assert_equal "pl", @user.reload.chat_language, "unknown languages are ignored"
    get director_path
    assert_select ".lang-switch button.is-active", text: "PL"
    assert_select ".content > .chat-app [data-voice-done]", 1
  end

  test "spec 019: the verifier on the Team page and the button in the chat; other users cannot use mine" do
    codex = Executor.create!(name: "Codex", preset: "codex")
    wera = Agent.create!(user: @user, name: "Wera", master_prompt: "x", executor: codex)
    @user.team_roles.create!(agent: @director, role: "director")
    get director_path
    assert_select "button[data-verify]", 0, "no verifier, no button"
    post team_roles_path, params: { team_role: { role: "verifier", agent_id: wera.id } }
    assert_equal "Wera is now your verifier.", flash[:notice]
    get team_path
    assert_select ".org-node.is-verifier", text: /Wera/
    get director_path
    assert_select "form[action='#{verify_director_path}'] button[data-verify]"
    assert_select ".content > .chat-app [data-voice-verify]", 1
    post verify_director_path, headers: { "Accept" => "application/json" }
    assert_equal({ "ok" => true, "active" => true, "writing" => true }, JSON.parse(response.body), "invited: checks the conversation at once")
    assert @user.reload.verifier_active?
    assert_equal 1, TaskRun.where(user: @user, purpose: "verify").count
    post verify_director_path, headers: { "Accept" => "application/json" }
    assert_equal false, JSON.parse(response.body)["active"], "pressed again: sent away"
    assert_not @user.reload.verifier_active?
    @user.chat_messages.create!(author: "verifier", content: "<b>Check</b> this")
    get director_path
    assert_select ".bubble-row.from-verifier .bubble-name", text: "Wera · verifier"
    assert_select ".bubble-row.from-verifier .bubble-text", text: "<b>Check</b> this"

    sign_in(create_user(username: "bob"))
    post verify_director_path, headers: { "Accept" => "application/json" }
    assert_response :unprocessable_content
    assert_equal 1, TaskRun.where(purpose: "verify").count, "bob has no verifier; mine is not his"
  end

  test "owner fixes: spoken messages are marked; the speech speed is saved per user" do
    @user.team_roles.create!(agent: @director, role: "director")
    post chat_messages_path, params: { chat_message: { content: "Hej", spoken: "1" } }, headers: { "Accept" => "application/json" }
    assert @user.chat_messages.last.spoken?
    get director_path
    assert_select ".speed-switch button.is-active", text: "1,5×"
    patch speech_speed_director_path, params: { speed: "2.0" }, as: :json
    assert_equal 2.0, JSON.parse(response.body)["speed"]
    patch speech_speed_director_path, params: { speed: "9" }, as: :json
    assert_equal 2.0, @user.reload.speech_speed.to_f, "only the offered speeds"
  end

  test "auto refresh stamp changes with new chat messages" do
    get stamp_director_path, headers: { "Accept" => "application/json" }
    first = JSON.parse(response.body)["stamp"]
    @user.chat_messages.create!(author: "director", content: "hi")
    get stamp_director_path, headers: { "Accept" => "application/json" }
    assert_not_equal first, JSON.parse(response.body)["stamp"]
  end

  # Spec 021: a stand-in agent ("claude" on PATH) answers with text or JSON.
  def with_director_answer(answer)
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "answer"), answer.is_a?(String) ? answer : answer.to_json)
      File.write(File.join(bin, "claude"), "#!/bin/sh\ncat > /dev/null\ncat \"#{bin}/answer\"\n")
      File.chmod(0o755, File.join(bin, "claude"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      yield
    ensure
      ENV["PATH"] = original
    end
  end

  def blocked_epic
    item = @user.work_items.create!(title: "World review", state: "blocked", blocked_reason: "Step 2 failed", started_at: 5.minutes.ago)
    run = ->(step, state, output = nil) { TaskRun.create!(user: @user, work_item: item, epic_step: step, agent: @member, purpose: "epic_step", trigger: "scheduled", occurrence_start: Time.current, state: state, output: output) }
    first = item.epic_steps.create!(position: 1, title: "Find topics", agent: @member, state: "succeeded")
    run.(first, "succeeded", "Topics found: [Topic A], [Topic B]")
    second = item.epic_steps.create!(position: 2, title: "Check sources", agent: @member, state: "failed")
    item.epic_steps.create!(position: 3, title: "Summary", agent: @member)
    [ item, second, run.(second, "failed") ]
  end

  test "spec 021: chat and verification show the topics while the next step is running" do
    @user.team_roles.create!(agent: @director, role: "director")
    @user.team_roles.create!(agent: @member, role: "verifier")
    item, second, attempt = blocked_epic
    item.update!(state: "planned", blocked_reason: nil)
    second.update!(state: "running")
    attempt.update!(state: "running", output: "unfinished source check")

    post chat_messages_path, params: { chat_message: { content: "Which topics did the topic-selection step find?" } }
    chat = TaskRun.find_by!(user: @user, purpose: "chat")
    with_director_answer(reply: "The topics were [Topic A] and [Topic B].", actions: []) do
      ManagementRunner.new(chat).perform!
    end
    post verify_director_path
    verification = TaskRun.find_by!(user: @user, purpose: "verify")
    with_director_answer("The step result confirms both topics.") do
      ManagementRunner.new(verification).perform!
    end

    [ chat, verification ].each do |run|
      assert_match "| Topics found: [Topic A], [Topic B]", run.reload.prompt
      assert_no_match "unfinished source check", run.prompt
      assert_equal "succeeded", run.state
    end
    get director_path
    assert_select ".bubble", text: /The topics were \[Topic A\] and \[Topic B\]/
    assert_select ".bubble", text: /The step result confirms both topics/
    assert_equal "running", second.reload.state
  end

  test "spec 021: the user asks in the chat to retry a failed step; the director's retry is applied once" do
    @user.team_roles.create!(agent: @director, role: "director")
    @user.team_roles.create!(agent: @member, role: "member")
    item, second, failed = blocked_epic
    post chat_messages_path, params: { chat_message: { content: "Ponów krok 2 w World review" } }
    chat = TaskRun.where(user: @user, purpose: "chat", state: "queued").sole
    with_director_answer(reply: "Jasne, ponawiam.", actions: [ { type: "retry_step", id: item.id, step: 2, attempt: failed.id } ]) do
      ManagementRunner.new(chat).perform!
    end
    assert_match "| Topics found: [Topic A], [Topic B]", chat.reload.prompt.to_s, "the director saw the answer of step 1"
    assert_equal [ "planned", %w[succeeded queued pending] ], [ item.reload.state, item.epic_steps.map(&:state) ]
    assert_equal 1, second.runs.where(state: "queued").count
    assert_equal 1, item.epic_steps.first.runs.count
    get director_path
    assert_select ".bubble-actions", text: /Retrying step 2 "Check sources" of "World review"/

    post chat_messages_path, params: { chat_message: { content: "Ponów krok 2 w World review jeszcze raz" } }
    stale = TaskRun.where(user: @user, purpose: "chat", state: "queued").sole
    with_director_answer(reply: "Ponawiam.", actions: [ { type: "retry_step", id: item.id, step: 2, attempt: failed.id } ]) do
      ManagementRunner.new(stale).perform!
    end
    assert_match "not blocked", @user.chat_messages.ordered.last.content, "the stale retry is refused and the reason reported"
    assert_equal 1, item.runs.where(state: %w[queued running]).count
  end

  test "spec 021: without a clear request from the user the retry is refused; Try again on the page still works" do
    @user.team_roles.create!(agent: @director, role: "director")
    item, second, failed = blocked_epic
    post chat_messages_path, params: { chat_message: { content: "What did the topic step find?" } }
    chat = TaskRun.where(user: @user, purpose: "chat", state: "queued").sole
    with_director_answer(reply: "Retrying.", actions: [ { type: "retry_step", id: item.id, step: 2, attempt: failed.id } ]) do
      ManagementRunner.new(chat).perform!
    end
    assert_match "has not asked in their message", @user.chat_messages.ordered.last.content
    assert_equal [ "blocked", 1 ], [ item.reload.state, second.runs.count ]

    post retry_work_item_path(item)
    assert_equal [ "planned", %w[succeeded queued pending] ], [ item.reload.state, item.epic_steps.map(&:state) ]
    assert_equal 1, item.epic_steps.first.runs.count
  end
end
