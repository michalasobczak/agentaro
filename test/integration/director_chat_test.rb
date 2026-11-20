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
    assert_select "[data-typing]:not([hidden])", 1, "the director is writing"
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
    get project_path(item.project)
    assert_select ".kanban-card", text: /Backup summary.*high/m
    get work_item_path(item)
    assert_select "dd", text: "Which tools?"
    assert_select ".breadcrumbs li", 3
    assert_select ".breadcrumbs a[href='#{projects_path}']", text: "Projects"
    assert_select ".breadcrumbs a[href='#{project_path(item.project)}']", text: "General"
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
    get projects_path
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
    assert_select "[data-chat-dock]", 0
    assert_select ".chat-app:not(.is-dock)", 1
  end

  test "floating chat opening for the first time gets the latest 100 messages" do
    @user.team_roles.create!(agent: @director, role: "director")
    ids = 105.times.map { |i| @user.chat_messages.create!(author: "user", content: "m#{i}").id }
    get chat_messages_path, headers: { "Accept" => "application/json" }
    assert_equal ids.last(100), JSON.parse(response.body)["messages"].map { |m| m["id"] }
    get chat_messages_path(after: ids[1]), headers: { "Accept" => "application/json" }
    assert_equal ids[2, 100], JSON.parse(response.body)["messages"].map { |m| m["id"] }
  end

  test "auto refresh stamp changes with new chat messages" do
    get stamp_director_path, headers: { "Accept" => "application/json" }
    first = JSON.parse(response.body)["stamp"]
    @user.chat_messages.create!(author: "director", content: "hi")
    get stamp_director_path, headers: { "Accept" => "application/json" }
    assert_not_equal first, JSON.parse(response.body)["stamp"]
  end
end
