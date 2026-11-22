require "test_helper"

# Spec 048: the buttons on the epic's page and in the work panel, and the chat actions on the owner's words.
class PauseEpicIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    executor = Executor.create!(name: "Claude", preset: "claude_code")
    @agent = Agent.create!(user: @user, name: "Pisarz", master_prompt: "You write.", executor: executor)
    @director = Agent.create!(user: @user, name: "Dyrektor", master_prompt: "You direct.", executor: executor)
    @user.team_roles.create!(agent: @director, role: "director")
    @user.team_roles.create!(agent: @agent, role: "member")
    space = @user.spaces.create!(kind: "project", name: "Gra", goal: "Gra")
    @city = @user.work_items.create!(title: "Miasto", space: space, state: "planned")
    2.times { |i| @city.epic_steps.create!(position: i + 1, title: "Krok #{i + 1}", agent: @agent, state: "pending") }
    sign_in(@user)
  end

  test "G1, G3, G5: Pause and Resume on the epic's page; the page and the panel say so" do
    get work_item_path(@city)
    assert_select "button", text: "Pause"
    post pause_work_item_path(@city)
    assert @city.reload.paused?
    follow_redirect!
    assert_select ".pause-note", text: /Paused since \d\d:\d\d/
    assert_select ".badge", text: "paused"
    assert_select "[style]", 0
    get work_director_path, as: :json
    epic = response.parsed_body["spaces"].flat_map { |s| s["epics"] }.find { |e| e["id"] == @city.id }
    assert_equal [ "paused", resume_work_item_path(@city) ], [ epic["paused"], epic["pause_url"] ]
    post resume_work_item_path(@city), as: :json
    assert_equal({ "ok" => true, "paused" => false }, response.parsed_body)
  end

  test "R2, negative: another user's epic cannot be paused; a done epic says why" do
    other = create_user(username: "bob").work_items.create!(title: "Bob", state: "planned")
    post pause_work_item_path(other)
    assert_response :not_found
    @city.update!(state: "done")
    post pause_work_item_path(@city), as: :json
    assert_response :unprocessable_content
    assert_match "only a planned epic can be paused", response.parsed_body["error"]
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

  test "S4: \"wstrzymaj miasto\" pauses it; the director then sees it paused; without such words nothing changes" do
    pause = [ { type: "pause_epic", id: @city.id } ]
    reply = chat("Wstrzymaj miasto.", { reply: "Wstrzymuję.", actions: pause }, { reply: "ok", actions: pause })
    assert @city.reload.paused?
    assert_match "Paused: Miasto", reply.actions_summary
    prompt = TaskRun.where(purpose: "chat").order(:id).last.model_calls.order(:position).first.prompt_text
    chat("Co z miastem?", { reply: "Stoi.", actions: [] })
    prompt = TaskRun.where(purpose: "chat").order(:id).last.model_calls.order(:position).first.prompt_text
    assert_match "paused by alice: paused since", prompt
    resume = [ { type: "resume_epic", id: @city.id } ]
    chat("Co u ciebie?", { reply: "Wznawiam.", actions: resume }, { reply: "x", actions: resume }, { reply: "x", actions: resume })
    assert @city.reload.paused?, "no words about pausing or resuming, no change"
    chat("Wznów miasto.", { reply: "Wznawiam.", actions: resume }, { reply: "ok", actions: resume })
    assert_not @city.reload.paused?
  end
end
