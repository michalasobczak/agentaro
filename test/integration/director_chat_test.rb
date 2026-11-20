require "test_helper"

# Spec 011: chat (G1), list and item pages (G2, G8), team and org chart (G3, G4), permissions (S4).
class DirectorChatTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @executor = Executor.create!(name: "Claude", preset: "claude_code")
    @director = Agent.create!(user: @user, name: "Dyrektor", master_prompt: "x", executor: @executor)
    @manager = Agent.create!(user: @user, name: "Kierownik", master_prompt: "x", executor: @executor)
    sign_in(@user)
  end

  test "G3, G4: build the team on the team page and see the org chart" do
    get team_path
    assert_select ".org", 0
    post team_roles_path, params: { team_role: { role: "director", agent_id: @director.id } }
    post team_roles_path, params: { team_role: { role: "manager", agent_id: @manager.id } }
    manager_role = @user.team_roles.managers.sole
    post team_roles_path, params: { team_role: { role: "member", agent_id: @director.id, parent_id: manager_role.id, role_text: "reviewer" } }
    get team_path
    assert_select ".org-node.is-director", text: /Dyrektor/
    assert_select ".org-node.is-manager", text: /Kierownik/
    assert_select ".org ul ul .org-node", text: /reviewer.*Dyrektor/m
    assert_select "[style]", 0

    post team_roles_path, params: { team_role: { role: "director", agent_id: @manager.id } }
    assert_equal "You already have a director", flash[:alert]
    delete team_role_path(manager_role)
    assert_equal 1, @user.team_roles.count, "a manager leaves with their team"
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

  test "G2, G8: the list and an item's history; Try again on a blocked item" do
    @user.team_roles.create!(agent: @director, role: "director")
    item = @user.work_items.create!(title: "Backup summary", state: "blocked", blocked_reason: "Which tools?", priority: "high")
    get work_items_path
    assert_select ".row-link", text: /Backup summary.*high priority/m
    get work_item_path(item)
    assert_select "dd", text: "Which tools?"
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
    get work_items_path
    assert_no_match "Bob's secret", response.body
    delete team_role_path(bob.team_roles.create!(agent: Agent.create!(user: bob, name: "B", master_prompt: "x", executor: @executor), role: "director"))
    assert_response :not_found
  end

  test "auto refresh stamp changes with new chat messages" do
    get stamp_director_path, headers: { "Accept" => "application/json" }
    first = JSON.parse(response.body)["stamp"]
    @user.chat_messages.create!(author: "director", content: "hi")
    get stamp_director_path, headers: { "Accept" => "application/json" }
    assert_not_equal first, JSON.parse(response.body)["stamp"]
  end
end
