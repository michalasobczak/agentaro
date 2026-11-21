require "test_helper"

# Spec 031: the Brain page (G7, R2, R3, S3) and "remember" / "forget" in the chat (G8).
class BrainPageTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @executor = Executor.create!(name: "Claude", preset: "claude_code")
    @director = Agent.create!(user: @user, name: "Anna", master_prompt: "You direct.", executor: @executor)
    @user.team_roles.create!(agent: @director, role: "director")
    @space = @user.spaces.create!(name: "Home", kind: "team")
    @episode = MemoryEpisode.record!(@user, "user_message", "Raporty zawsze po polsku, proszę.")
    @fact = @user.memory_facts.create!(subject_type: "user", statement: "Raporty po polsku.", kind: "preference")
    @fact.memory_fact_sources.create!(memory_episode: @episode)
    @proposed = @user.memory_facts.create!(subject_type: "user", statement: "Lubi kawę <b>czarną</b>.", kind: "preference", status: "proposed")
    sign_in(@user)
  end

  test "G7, S3: the page shows blocks, facts with their source, and profile facts waiting for approval; escaped; no inline style" do
    get brain_path
    assert_response :success
    assert_select "#proposed .brain-fact", text: /Lubi kawę <b>czarną<\/b>\./
    assert_select "#facts .brain-fact", text: /Raporty po polsku\..*Why \(1 source\).*Raporty zawsze po polsku, proszę\./m
    assert_select "#blocks textarea[name=content]", 3 # about you, the space, the director
    assert_select ".brain-status", text: /not reachable/
    assert_select "nav a[href='#{brain_path}']"
    assert_select "[style]", 0
  end

  test "R2: keep and drop; G1: a block is saved; R3: an edit is a new version with history; pin; delete is for good; S3" do
    post approve_memory_fact_path(@proposed)
    assert_equal "active", @proposed.reload.status
    other = @user.memory_facts.create!(subject_type: "user", statement: "Drop me.", kind: "fact", status: "proposed")
    post reject_memory_fact_path(other)
    assert_equal "invalid", other.reload.status

    patch block_brain_path, params: { scope_type: "space", scope_id: @space.id, content: "Backups weekly." }
    assert_equal "Backups weekly.", MemoryBlock.for(@user, "space", @space.id).content

    patch memory_fact_path(@fact), params: { statement: "Raporty po angielsku.", kind: "decision" }
    edited = @fact.reload.superseded_by
    assert_equal [ "invalid", "Raporty po angielsku.", "edited", "decision" ], [ @fact.status, edited.statement, edited.origin, edited.kind ]
    get brain_path
    assert_select "#fact-#{edited.id}", text: /History \(1\).*Raporty po polsku\./m

    post pin_memory_fact_path(edited)
    assert edited.reload.pinned
    delete memory_fact_path(edited)
    assert_not MemoryFact.exists?(edited.id)
    item = @user.work_items.create!(title: "Report", space: @space, state: "planned", started_at: 1.minute.ago)
    step = item.epic_steps.create!(position: 1, title: "Write", agent: @director, state: "queued")
    assert_no_match "Raporty po angielsku", StepChain.prompt_for(step, @director).text, "a deleted fact is no longer in prompts"
  end

  test "R4: another user's facts and blocks cannot be changed" do
    other = create_user(username: "other1")
    theirs = other.memory_facts.create!(subject_type: "user", statement: "Theirs.", kind: "fact", status: "proposed")
    [ -> { post approve_memory_fact_path(theirs) }, -> { delete memory_fact_path(theirs) }, -> { patch memory_fact_path(theirs), params: { statement: "x" } } ].each do |request|
      request.call
      assert_response :not_found
    end
    assert_equal [ "proposed", "Theirs." ], theirs.reload.values_at(:status, :statement)
    patch block_brain_path, params: { scope_type: "space", scope_id: other.spaces.create!(name: "X", kind: "team").id, content: "Mine now" }
    assert_equal 0, MemoryBlock.where(content: "Mine now").count
  end

  test "Q5 withdrawn: the page no longer offers to read the earlier chat history" do
    get brain_path
    assert_no_match "earlier chat history", response.body
  end

  # --- G8: remember and forget in the chat -------------------------------------------------------

  def with_director_answer(answer)
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "claude"), "#!/bin/sh\ncat > /dev/null\necho '#{answer.to_json.gsub("'", "'\\\\''")}'\n")
      File.chmod(0o755, File.join(bin, "claude"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      yield
    ensure
      ENV["PATH"] = original
    end
  end

  def chat(content, answer)
    @user.chat_messages.create!(author: "user", content: content)
    with_director_answer(answer) do
      run = ManagementRunner.chat!(@user)
      ManagementRunner.new(run.reload).perform!
    end
    @user.chat_messages.where(author: "director").order(:id).last
  end

  test "G8: \"zapamiętaj\" remembers at once (approved), \"zapomnij\" forgets by id; the director sees facts with their ids" do
    reply = chat("Zapamiętaj, że raporty mają być krótkie.",
                 { reply: "Zapamiętam.", actions: [ { type: "remember", subject: "user", kind: "preference", statement: "Raporty mają być krótkie." } ] })
    remembered = @user.memory_facts.find_by!(statement: "Raporty mają być krótkie.")
    assert_equal [ "active", "remembered" ], remembered.values_at(:status, :origin)
    assert_match "Remembered: Raporty mają być krótkie.", reply.actions_summary
    assert_equal [ "Zapamiętaj, że raporty mają być krótkie." ], remembered.episodes.map(&:excerpt)

    reply = chat("Zapomnij o tym.", { reply: "Zapomniane.", actions: [ { type: "forget", id: remembered.id } ] })
    assert_equal "invalid", remembered.reload.status
    assert_match "Forgotten", reply.actions_summary
    prompt = TaskRun.where(purpose: "chat").order(:id).last.model_calls.first.prompt_text
    assert_match "[#{@fact.id}] Raporty po polsku.", prompt
  end

  test "G8, R1: without the user asking, the director cannot remember or approve anything" do
    chat("Jak leci?", { reply: "Dobrze.", actions: [ { type: "remember", subject: "user", statement: "Lubi być pytany, jak leci." },
                                                     { type: "approve_facts", ids: [ @proposed.id ] } ] })
    assert_nil @user.memory_facts.find_by(statement: "Lubi być pytany, jak leci.")
    assert_equal "proposed", @proposed.reload.status
  end

  test "Q3: answering the daily list keeps the facts named" do
    chat("Zostaw wszystkie.", { reply: "Zostawiam.", actions: [ { type: "approve_facts", ids: [ @proposed.id ] } ] })
    assert_equal "active", @proposed.reload.status
  end
end
