require "test_helper"

# Spec 008: admin management (G1–G6), read-only list for users (G7, Q4, S2), presets only (Q3, S3).
class ExecutorsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user(username: "root1", role: "admin")
    @user = create_user
  end

  test "admins add, edit, disable and delete executors" do
    sign_in(@admin)
    get new_admin_executor_path
    assert_select "select[name='executor[preset]'] optgroup", 2
    assert_select "input[name*=program], input[name*=argument]", 0

    post admin_executors_path, params: { executor: { name: "Local Ollama", preset: "ollama_api", enabled: "1" } }
    assert_redirected_to executors_path
    executor = Executor.find_by!(name: "Local Ollama")
    assert_equal "http://localhost:11434", executor.base_url

    patch admin_executor_path(executor), params: { executor: { enabled: "0", default_model: "qwen3:8b" } }
    assert_equal [ false, "qwen3:8b" ], [ executor.reload.enabled, executor.default_model ]

    post admin_executors_path, params: { executor: { name: "local ollama", preset: "ollama_api" } }
    assert_response :unprocessable_content
    assert_match "Name has already been taken", response.body

    delete admin_executor_path(executor)
    assert_not Executor.exists?(executor.id)
    assert_equal %w[create update destroy], DataChange.where(record_type: "Executor", record_id: executor.id).order(:id).pluck(:action)
  end

  test "S3, Q3: a forged program, arguments or unknown preset change nothing" do
    sign_in(@admin)
    post admin_executors_path, params: { executor: { name: "Evil", preset: "claude_code", program: "/bin/sh", arguments: "-c id", version_args: "x" } }
    executor = Executor.find_by!(name: "Evil")
    assert_equal "claude", executor.preset_definition.program
    assert_equal [ "--version" ], executor.preset_definition.version_args

    post admin_executors_path, params: { executor: { name: "Shell", preset: "custom" } }
    assert_response :unprocessable_content
    assert_not Executor.exists?(name: "Shell")
  end

  test "admins check an executor and see the result" do
    sign_in(@admin)
    executor = Executor.create!(name: "Down", preset: "ollama_api", base_url: "http://127.0.0.1:#{TCPServer.new("127.0.0.1", 0).then { |s| s.addr[1].tap { s.close } }}")
    post check_admin_executor_path(executor)
    assert_redirected_to executors_path
    follow_redirect!
    assert_match "Down: check failed.", response.body
    assert_select ".check-output pre", text: /Could not connect/
    assert_equal false, executor.reload.last_check_ok
  end

  test "G7, S2: users see the list read-only, without addresses or output" do
    Executor.create!(name: "Lab box", preset: "lm_studio_api", base_url: "http://10.0.0.5:1234/v1", notes: "internal", default_model: "gpt-oss",
                     last_checked_at: Time.current, last_check_ok: true, last_check_output: "Models: secret-model")
    sign_in(@user)
    get executors_path
    assert_response :success
    assert_select "td", text: "Lab box"
    assert_select "td", text: "gpt-oss"
    assert_no_match "10.0.0.5", response.body
    assert_no_match "internal", response.body
    assert_no_match "secret-model", response.body
    assert_select "a[href='#{new_admin_executor_path}']", 0
    assert_select "form[action*='/admin/executors']", 0
  end

  test "S2: users get 403 on every change" do
    executor = Executor.create!(name: "Claude", preset: "claude_code")
    sign_in(@user)
    get new_admin_executor_path
    assert_response :forbidden
    post admin_executors_path, params: { executor: { name: "X", preset: "codex" } }
    assert_response :forbidden
    get edit_admin_executor_path(executor)
    assert_response :forbidden
    patch admin_executor_path(executor), params: { executor: { enabled: "0" } }
    assert_response :forbidden
    post check_admin_executor_path(executor)
    assert_response :forbidden
    delete admin_executor_path(executor)
    assert_response :forbidden
    assert_equal [ true, nil ], [ executor.reload.enabled, executor.last_checked_at ]
    assert_equal 1, Executor.count
  end

  test "notes and default model are optional" do
    sign_in(@admin)
    get new_admin_executor_path
    assert_select "label[for=executor_notes]", text: "Notes (optional)"
    assert_select "textarea[name='executor[notes]'][required]", 0
    post admin_executors_path, params: { executor: { name: "Bare", preset: "codex", notes: "", default_model: "" } }
    assert_redirected_to executors_path
    assert_equal [ nil, nil ], Executor.find_by!(name: "Bare").then { |e| [ e.notes, e.default_model ] }
  end

  test "form fields stay inside their panel (owner fix)" do
    css = Rails.root.join("app/assets/stylesheets/application.css").read
    assert_match(/\.field \{[^}]*grid-template-columns: minmax\(0, 1fr\)/, css)
    base = css[/input\[type=text\][^{]*\{/]
    %w[input[type=url] select textarea].each { |sel| assert_includes base, sel }
  end

  test "signed-out visitors are sent to sign in" do
    get executors_path
    assert_redirected_to new_session_path
  end

  test "pages have no inline styles" do
    sign_in(@admin)
    executor = Executor.create!(name: "Claude", preset: "claude_code", last_checked_at: Time.current, last_check_ok: true, last_check_output: "2.1")
    [ executors_path, new_admin_executor_path, edit_admin_executor_path(executor) ].each do |path|
      get path
      assert_response :success
      assert_select "[style]", 0, path
      assert_select "script:not([src])", 0, path
    end
  end

  # Spec 055, G1, G5: opencode is offered; once added, the Executors page says plainly that it has no sandbox.
  test "spec 055: an admin adds opencode; the page warns that it runs without a sandbox" do
    sign_in(@admin)
    get executors_path
    assert_select ".opencode-note", 0
    get new_admin_executor_path
    assert_select "option[value=opencode]", text: "opencode"
    assert_select ".hint", text: /opencode runs without a sandbox/
    post admin_executors_path, params: { executor: { name: "Darmowy DeepSeek", preset: "opencode", enabled: "1" } }
    assert_equal "opencode/deepseek-v4.1-flash-free", Executor.find_by!(name: "Darmowy DeepSeek").default_model
    get executors_path
    assert_select ".opencode-note", text: /opencode runs without a sandbox.*Agentaro's databases and secrets.*opencode's servers/m
    assert_select "[style]", 0
  end
end

