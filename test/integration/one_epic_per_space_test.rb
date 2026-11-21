require "test_helper"

# Spec 037, S5: the waiting epic says which epic of its space it waits for — on its page, on the space's board and
# in the director's work list; titles escaped, no inline style.
class OneEpicPerSpacePagesTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    executor = Executor.create!(name: "Claude", preset: "claude_code")
    @director = Agent.create!(user: @user, name: "Anna", master_prompt: "You direct.", executor: executor)
    @writer = Agent.create!(user: @user, name: "Pisarz", master_prompt: "You write.", executor: executor)
    @user.team_roles.create!(agent: @director, role: "director")
    @space = @user.spaces.create!(name: "Gra", kind: "team")
    @a = @user.work_items.create!(title: "MVP <b>gry</b>", state: "blocked", space: @space, started_at: 1.hour.ago, blocked_reason: "Step 6 asks")
    @b = @user.work_items.create!(title: "Większa mapa", state: "planned", space: @space)
    @b.epic_steps.create!(position: 1, title: "Map", agent: @writer)
    sign_in(@user)
  end

  test "S5: the epic page and the board name the epic it waits for" do
    get work_item_path(@b)
    assert_select "dd", text: /Waits for “MVP <b>gry<\/b>” in this space/
    assert_select "dd a[href='#{work_item_path(@a)}']"
    get space_path(@space)
    assert_select ".kanban-note", text: "Waits for “MVP <b>gry</b>” in this space"
    assert_select "[style]", 0

    get work_item_path(@a)
    assert_select "dd", text: /Waits for/, count: 0
  end

  test "S5: the director's work list shows the waiting line" do
    @user.chat_messages.create!(author: "user", content: "Co z mapą?")
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "claude"), "#!/bin/sh\ncat > /dev/null\necho '{\"reply\": \"Czeka.\", \"actions\": []}'\n")
      File.chmod(0o755, File.join(bin, "claude"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      run = ManagementRunner.chat!(@user)
      ManagementRunner.new(run.reload).perform!
    ensure
      ENV["PATH"] = original
    end
    prompt = TaskRun.where(purpose: "chat").order(:id).last.model_calls.first.prompt_text
    assert_match "waits for id #{@a.id} \"MVP <b>gry</b>\" in this space", prompt
  end
end
