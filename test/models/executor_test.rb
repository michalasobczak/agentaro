require "test_helper"

# Spec 008: presets (Q3), validations (S4, R5, R7), the check (G4, R2, R4, S5).
class ExecutorTest < ActiveSupport::TestCase
  def executor(**attrs) = Executor.new({ name: "Claude", preset: "claude_code" }.merge(attrs))

  test "presets define what runs; the record holds no program or arguments" do
    assert_equal %w[claude codex codex opencode gemini grok ollama lms], Executor::PRESETS.values.select(&:cli?).map(&:program) # spec 049: codex_local runs codex too; spec 055: opencode
    assert_equal %w[ollama_api lm_studio_api openai_compatible_api], Executor::PRESETS.values.select(&:api?).map(&:key)
    assert_not_includes Executor.column_names, "program"
    assert_not_includes Executor.column_names, "arguments"
    assert Executor::PRESETS.frozen?
  end

  test "S4: name required and unique; preset must be known" do
    assert executor.tap(&:save!).persisted?
    assert_not executor(name: "claude").valid?, "names are unique regardless of case"
    assert_not executor(name: " ").valid?
    assert_not executor(name: "x" * 61).valid?
    bad = executor(name: "Other", preset: "bash")
    assert_not bad.valid?
    assert_includes bad.errors.full_messages, "Preset is not one of the presets"
  end

  test "API presets get the default address; CLI presets have none" do
    api = executor(preset: "ollama_api").tap(&:validate)
    assert_equal "http://localhost:11434", api.base_url
    cli = executor(base_url: "http://localhost:1").tap(&:validate)
    assert_nil cli.base_url
  end

  test "R5: base URL is http(s) without credentials, query or fragment" do
    assert executor(preset: "lm_studio_api", base_url: "http://other-host:1234/v1/").tap(&:validate).valid?
    { "ftp://host/" => "must start with http:// or https://", "file:///etc/passwd" => "must start with http:// or https://",
      "http://user:secret@host" => "must not contain a user name or password", "http://host/v1?key=1" => "must not contain a query or fragment",
      "http://host/#x" => "must not contain a query or fragment", "http://ho st" => "is not a valid address" }.each do |url, message|
      e = executor(preset: "ollama_api", base_url: url)
      assert_not e.valid?, url
      assert_includes e.errors[:base_url], message, url
    end
  end

  test "locate finds only executable files on PATH or the usual folders" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "tool"), "#!/bin/sh\n")
      assert_nil ExecutorCheck.locate("tool", path: dir), "not executable"
      File.chmod(0o755, File.join(dir, "tool"))
      assert_equal File.join(dir, "tool"), ExecutorCheck.locate("tool", path: dir)
      assert_nil ExecutorCheck.locate("no-such-tool-#{SecureRandom.hex(4)}", path: dir)
    end
  end

  # A stand-in program on PATH, so the check runs a real process without needing the vendor tools.
  def with_fake_program(name, script)
    Dir.mktmpdir do |dir|
      path = File.join(dir, name)
      File.write(path, "#!/bin/sh\n#{script}\n")
      File.chmod(0o755, path)
      original = ENV["PATH"]
      ENV["PATH"] = "#{dir}:#{original}"
      yield
    ensure
      ENV["PATH"] = original
    end
  end

  test "G4: a CLI check runs the preset's version argument and keeps the answer" do
    with_fake_program("codex", %(echo "args=$*"; printf '\\033[1mcodex-cli 9.9\\033[0m\\n')) do
      e = executor(name: "Codex", preset: "codex").tap(&:save!)
      result = e.check!
      assert result.ok
      assert_equal "args=--version\ncodex-cli 9.9", e.reload.last_check_output, "fixed arguments, escape codes removed"
      assert e.last_check_ok
      assert e.last_checked_at
    end
  end

  test "R4: the program gets a minimal environment without Agentaro's secrets, in the temp folder" do
    ENV["AGENTARO_TEST_SECRET"] = "s3cret"
    with_fake_program("claude", %(echo "secret=${AGENTARO_TEST_SECRET:-none} base=${SECRET_KEY_BASE:-none} home=${HOME:+set}"; pwd)) do
      result = ExecutorCheck.new(executor).run
      assert result.ok
      assert_match "secret=none base=none home=set", result.output
      assert_equal File.realpath(Dir.tmpdir), File.realpath(result.output.lines.last.strip)
    end
  ensure
    ENV.delete("AGENTARO_TEST_SECRET")
  end

  test "S5: failures are reported, not raised" do
    with_fake_program("gemini", "echo broken >&2; exit 3") do
      result = ExecutorCheck.new(executor(preset: "gemini_cli")).run
      assert_not result.ok
      assert_equal "Exited with status 3. broken", result.output
    end
  end

  test "S5: a program that hangs is stopped after the timeout, with its children" do
    with_fake_program("ollama", "sleep 30 & sleep 30") do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = ExecutorCheck.new(executor(preset: "ollama_cli"), timeout: 1).run
      assert_not result.ok
      assert_equal "No answer within 1 seconds; stopped.", result.output
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 5
    end
  end

  test "output is limited to 2 KB" do
    with_fake_program("claude", "head -c 100000 /dev/zero | tr '\\0' 'a'") do
      result = ExecutorCheck.new(executor).run
      assert result.ok
      assert_equal 2048, result.output.bytesize
    end
  end

  # A one-shot local HTTP server answering every request with the given status and body.
  def with_http_server(status, body)
    server = TCPServer.new("127.0.0.1", 0)
    requests = []
    thread = Thread.new do
      client = server.accept
      requests << client.gets
      while (line = client.gets) && line != "\r\n"; end
      client.write("HTTP/1.1 #{status}\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
      client.close
    rescue IOError, SystemCallError
      nil # the check may stop reading early (body limit)
    end
    yield "http://127.0.0.1:#{server.addr[1]}", requests
  ensure
    thread&.join(2)
    server&.close
  end

  test "G4: an API check lists the models (Ollama and OpenAI-compatible)" do
    with_http_server("200 OK", { models: [ { name: "qwen3:8b" }, { name: "llama3.2" } ] }.to_json) do |url, requests|
      result = ExecutorCheck.new(executor(preset: "ollama_api", base_url: url)).run
      assert result.ok
      assert_equal "Models: qwen3:8b, llama3.2", result.output
      assert_equal "GET /api/tags HTTP/1.1\r\n", requests.first
    end
    with_http_server("200 OK", { data: [ { id: "gpt-oss-20b" } ] }.to_json) do |url, requests|
      result = ExecutorCheck.new(executor(preset: "lm_studio_api", base_url: "#{url}/v1")).run
      assert_equal [ true, "Models: gpt-oss-20b" ], [ result.ok, result.output ]
      assert_equal "GET /v1/models HTTP/1.1\r\n", requests.first
    end
  end

  test "R5, S5: API errors, redirects and refused connections are failed checks" do
    with_http_server("302 Found", "") do |url|
      assert_equal [ false, "Answered 302 Found." ], ExecutorCheck.new(executor(preset: "ollama_api", base_url: url)).run.to_h.values
    end
    with_http_server("200 OK", "<html>") do |url|
      assert_equal [ false, "Answered, but not with a list of models." ], ExecutorCheck.new(executor(preset: "ollama_api", base_url: url)).run.to_h.values
    end
    with_http_server("200 OK", "[" + ("0," * 600_000) + "0]") do |url|
      assert_equal [ false, "Answered with more than 1 MB; not read." ], ExecutorCheck.new(executor(preset: "ollama_api", base_url: url)).run.to_h.values
    end
    port = TCPServer.new("127.0.0.1", 0).then { |s| s.addr[1].tap { s.close } }
    result = ExecutorCheck.new(executor(preset: "ollama_api", base_url: "http://127.0.0.1:#{port}")).run
    assert_not result.ok
    assert_match "Could not connect", result.output
  end
end
