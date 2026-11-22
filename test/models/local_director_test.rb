require "test_helper"
require "socket"

# Spec 044, G1/G2: the director on a local server gets a short prompt and a sized, structured request.
class LocalDirectorTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @user.spaces.create!(kind: "project", name: "Dom", goal: "Porządek")
  end

  def team_on(executor)
    director = Agent.create!(user: @user, name: "Dyrektor", master_prompt: "You direct.", executor: executor, model: "qwen3.5:9b")
    member = Agent.create!(user: @user, name: "Pisarz", master_prompt: "You write.", executor: executor, model: "qwen3.5:9b")
    @user.team_roles.create!(agent: director, role: "director")
    @user.team_roles.create!(agent: member, role: "member", role_text: "writer")
    director
  end

  def busy_history!
    space = @user.spaces.sole
    40.times { |i| @user.work_items.create!(title: "Epik numer #{i} " + "x" * 60, description: "opis " * 80, space: space, state: "new") }
    100.times { |i| @user.chat_messages.create!(author: i.even? ? "user" : "director", content: "Wiadomość #{i}: " + "treść rozmowy " * 120) }
  end

  def chat_prompt(director)
    run = TaskRun.create!(user: @user, agent: director, purpose: "chat", trigger: "manual", occurrence_start: Time.current, state: "queued")
    runner = ManagementRunner.new(run)
    runner.instance_variable_set(:@call_options, {})
    runner.send(:prompt_for, director)
  end

  test "S1: on a local server the chat prompt stays within 24 KB with 40 epics and 100 long messages" do
    director = team_on(Executor.create!(name: "Ollama", preset: "ollama_api"))
    busy_history!
    prompt = chat_prompt(director)
    assert_operator prompt.text.bytesize, :<=, 24 * 1024
    assert_match "Example: the user writes", prompt.text
    assert_equal 30, prompt.text.scan(/^- id \d+ "Epik numer/).size, "at most 30 epics, in the work list's order"
    assert_match "Wiadomość 99", prompt.text, "the latest message is there"
    assert_match "only in response to their own clear request", prompt.text, "R2: the safety rules stay"
  end

  test "negative: Claude Code keeps the full prompt" do
    director = team_on(Executor.create!(name: "Claude", preset: "claude_code"))
    busy_history!
    prompt = chat_prompt(director)
    assert_operator prompt.text.bytesize, :>, 60 * 1024
    assert_no_match(/Example: the user writes/, prompt.text)
  end

  # A one-request HTTP server that records the body and answers like Ollama (or refuses the first time).
  def with_ollama(answers)
    server = TCPServer.new("127.0.0.1", 0)
    bodies = []
    thread = Thread.new do
      answers.each do |status, body|
        client = server.accept
        head = +""
        head << client.gets until head.end_with?("\r\n\r\n")
        length = head[/Content-Length: (\d+)/i, 1].to_i
        bodies << JSON.parse(client.read(length))
        client.write("HTTP/1.1 #{status}\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
        client.close
      end
    end
    yield "http://127.0.0.1:#{server.addr[1]}", bodies
  ensure
    thread&.join(5)
    server&.close
  end

  test "S2: an Ollama director call carries the context size, the answer's schema and no thinking" do
    answer = { message: { content: { reply: "ok", actions: [] }.to_json }, done: true }.to_json
    with_ollama([ [ "200 OK", answer ] ]) do |url, bodies|
      executor = Executor.create!(name: "Ollama", preset: "ollama_api", base_url: url)
      director = team_on(executor)
      run = TaskRun.create!(user: @user, agent: director, purpose: "chat", trigger: "manual", occurrence_start: Time.current, state: "queued")
      outcome = AgentCall.new(run, director, AgentCall::Prompt.new(system: "s", user: "u" * 90_000), schema: DirectorSchema::CHAT).call
      assert_equal "succeeded", outcome.state
      body = bodies.sole
      assert_equal [ false, DirectorSchema::CHAT.deep_stringify_keys ], [ body["think"], body["format"] ]
      assert_equal 34_816 - 2048, body.dig("options", "num_ctx"), "90 KB of prompt needs about 30 k tokens plus room for the answer"
    end
  end

  test "resilience: a server that refuses the structured request is asked once more without it" do
    answer = { message: { content: "{\"reply\": \"ok\", \"actions\": []}" }, done: true }.to_json
    with_ollama([ [ "400 Bad Request", "{\"error\":\"format not supported\"}" ], [ "200 OK", answer ] ]) do |url, bodies|
      director = team_on(Executor.create!(name: "Ollama", preset: "ollama_api", base_url: url))
      run = TaskRun.create!(user: @user, agent: director, purpose: "chat", trigger: "manual", occurrence_start: Time.current, state: "queued")
      outcome = AgentCall.new(run, director, AgentCall::Prompt.new(system: "s", user: "u"), schema: DirectorSchema::CHAT).call
      assert_equal "succeeded", outcome.state
      assert_equal [ true, false ], bodies.map { |b| b.key?("format") }
    end
  end

  test "negative: a step's call (no schema) is sent as before" do
    answer = { message: { content: "done" }, done: true }.to_json
    with_ollama([ [ "200 OK", answer ] ]) do |url, bodies|
      director = team_on(Executor.create!(name: "Ollama", preset: "ollama_api", base_url: url))
      run = TaskRun.create!(user: @user, agent: director, purpose: "chat", trigger: "manual", occurrence_start: Time.current, state: "queued")
      AgentCall.new(run, director, AgentCall::Prompt.new(system: "s", user: "u")).call
      assert_equal %w[messages model stream], bodies.sole.keys.sort
    end
  end

  test "a local director that says it did something without an action still gets the proposal pass, which decides" do
    first = { message: { content: { reply: "Przechodzę na turbo.", actions: [] }.to_json }, done: true }.to_json + "\n"
    second = { message: { content: { reply: "ok", actions: [ { type: "set_tempo", level: 3 } ] }.to_json }, done: true }.to_json
    with_ollama([ [ "200 OK", first ], [ "200 OK", second ] ]) do |url, bodies|
      team_on(Executor.create!(name: "Ollama", preset: "ollama_api", base_url: url))
      @user.chat_messages.create!(author: "user", content: "Od teraz pracuj w tempie turbo.")
      ManagementRunner.new(ManagementRunner.chat!(@user).reload).perform!
      assert_equal 2, bodies.size
      assert_equal 3, @user.reload.work_tempo
      assert_match "Tempo: Turbo", @user.chat_messages.where(author: "director").last.actions_summary
    end
  end
end
