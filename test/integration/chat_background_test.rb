require "test_helper"

# Spec 029: chat background patterns — saved on the signed-in account, rendered by the server in both chat views,
# allowlisted on the way in and on the way out, and drawn only on the chat viewport.
class ChatBackgroundTest < ActionDispatch::IntegrationTest
  CSS = Rails.root.join("app/assets/stylesheets/application.css")

  setup do
    @user = create_user
    executor = Executor.create!(name: "Claude", preset: "claude_code")
    director = Agent.create!(user: @user, name: "Dyrektor", master_prompt: "x", executor: executor)
    @user.team_roles.create!(agent: director, role: "director")
    sign_in(@user)
  end

  def css = File.read(CSS)

  def assert_selector_shows(value, id)
    assert_select "form.chat-bg[action='#{account_chat_background_path}']" do
      assert_select "label[for=#{id}]", text: "Chat background"
      assert_select "select##{id}[name=chat_background] option", User::CHAT_BACKGROUNDS.size
      assert_select "select##{id} option[selected]", 1
      assert_select "select##{id} option[selected][value=#{value}]", text: User::CHAT_BACKGROUNDS[value]
    end
  end

  test "S1: Solid by default; both chat views offer the five labelled patterns" do
    get director_path
    assert_select "body[data-chat-background=solid]"
    assert_selector_shows "solid", "chat-background"
    assert_equal %w[Solid Dots Grid Gradient Animated], css_select("#chat-background option").map(&:text)
    assert_select "[style]", 0
    assert_select "script:not([src])", 0

    get spaces_path # the floating chat
    assert_select "body[data-chat-background=solid]"
    assert_select ".chat-app.is-dock"
    assert_selector_shows "solid", "chat-dock-background"
  end

  test "S2, R4: every pattern is saved, returned and rendered on the next page in both views" do
    User::CHAT_BACKGROUNDS.each_key do |value|
      patch account_chat_background_path, params: { chat_background: value }, as: :json
      assert_response :success
      assert_equal({ "chat_background" => value }, response.parsed_body)
      assert_equal value, @user.reload.chat_background
      get director_path
      assert_select "body[data-chat-background=#{value}]"
      assert_selector_shows value, "chat-background"
      get calendar_path
      assert_select "body[data-chat-background=#{value}]"
      assert_selector_shows value, "chat-dock-background"
    end
  end

  test "R4: without JavaScript the form posts and redirects back" do
    patch account_chat_background_path, params: { chat_background: "grid" }, headers: { "HTTP_REFERER" => spaces_url }
    assert_redirected_to spaces_url
    assert_equal "grid", @user.reload.chat_background
  end

  test "R4: missing, non-string and unknown values are refused with 422 and the saved choice stays" do
    @user.update!(chat_background: "dots")
    [ {}, { chat_background: "" }, { chat_background: "Dots" }, { chat_background: "pink; x" }, { chat_background: "dots " },
      { chat_background: [ "grid" ] }, { chat_background: { a: "grid" } }, { chat_background: 1 } ].each do |params|
      patch account_chat_background_path, params: params, as: :json
      assert_response :unprocessable_entity, params.inspect
      assert_equal({ "chat_background" => "dots" }, response.parsed_body)
      assert_equal "dots", @user.reload.chat_background
    end
    patch account_chat_background_path, params: { chat_background: "pink" }, headers: { "HTTP_REFERER" => spaces_url }
    assert_redirected_to spaces_url
    assert_equal "Unknown chat background.", flash[:alert]
    assert_equal "dots", @user.reload.chat_background
  end

  test "R3: an unrecognized stored value is rendered as Solid" do
    @user.update_column(:chat_background, "\"><script>x</script>")
    get director_path
    assert_select "body[data-chat-background=solid]"
    assert_selector_shows "solid", "chat-background"
    assert_no_match(/<script>x/, response.body)
  end

  test "S2: only the signed-in account changes; another session sees the saved choice; anonymous requests are refused" do
    other = create_user(username: "bob")
    patch account_chat_background_path, params: { chat_background: "animated", user_id: other.id }, as: :json
    assert_equal "animated", @user.reload.chat_background
    assert_equal "solid", other.reload.chat_background

    second = open_session { |s| s.https! }
    second.post session_path, params: { username: "alice", password: PASSWORD }
    second.get director_path
    assert_equal "animated", second.css_select("body").first["data-chat-background"]

    bobs = open_session { |s| s.https! }
    bobs.post session_path, params: { username: "bob", password: PASSWORD }
    bobs.get spaces_path
    assert_equal "solid", bobs.css_select("body").first["data-chat-background"]

    anonymous = open_session { |s| s.https! }
    anonymous.patch account_chat_background_path, params: { chat_background: "grid" }, as: :json
    assert_includes [ 401, 302 ], anonymous.response.status
    assert_equal "animated", @user.reload.chat_background
  end

  test "contract: a save without the CSRF token is refused; with it, it passes and is recorded in the data changelog" do
    ActionController::Base.allow_forgery_protection = true
    get director_path
    token = css_select("meta[name=csrf-token]").first["content"]
    patch account_chat_background_path, params: { chat_background: "grid" }, as: :json
    assert_response :unprocessable_entity
    assert_equal "solid", @user.reload.chat_background
    patch account_chat_background_path, params: { chat_background: "grid" }, headers: { "X-CSRF-Token" => token }, as: :json
    assert_response :success
    assert_equal "grid", @user.reload.chat_background
    change = DataChange.where(record_type: "User", record_id: @user.id, action: "update").last
    assert_equal [ "solid", "grid" ], JSON.parse(change.changeset)["chat_background"]
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  test "contract: theme and chat background are independent" do
    patch account_chat_background_path, params: { chat_background: "gradient" }, as: :json
    patch account_theme_path, params: { theme: "dark" }
    assert_equal [ "dark", "gradient" ], @user.reload.values_at(:theme, :chat_background)
    patch account_chat_background_path, params: { chat_background: "dots" }, as: :json
    assert_equal [ "dark", "dots" ], @user.reload.values_at(:theme, :chat_background)
    get director_path
    assert_select "body[data-theme=dark][data-chat-background=dots]"
  end

  test "R1, R6: each pattern is drawn only on the chat viewport, with colours for both palettes" do
    (User::CHAT_BACKGROUNDS.keys - [ "solid" ]).each do |value|
      rules = css.scan(/^([^{}\n]*data-chat-background="#{value}"[^{}\n]*)\{/).flatten
      assert rules.any?, "no rule for #{value}"
      rules.each { |selector| assert_match(/\.chat-scroll\s*\z/, selector.strip.sub(/\A@media[^{]*\{\s*/, ""), value) }
    end
    assert_match(/background:\s*var\(--bg\)/, css[/^\.chat-scroll\s*\{([^}]*)\}/, 1], "the opaque base stays")
    %w[--chat-dot --chat-line --chat-tint-1 --chat-tint-2].each do |token|
      assert_equal 3, css.scan(/^\s*#{token}:/).size, "#{token}: light, dark by choice, dark by system"
    end
  end

  test "S4, R6: the animated pattern stops under reduced motion and keeps a static gradient" do
    rule = css[/^body\[data-chat-background="animated"\] \.chat-scroll\s*\{([^}]*)\}/m, 1] or flunk "no animated rule"
    assert_match(/linear-gradient/, rule)
    assert_match(/animation:\s*chat-bg-drift\s/, rule)
    reduced = css.scan(/@media \(prefers-reduced-motion: reduce\) \{([^\n]*)\}\s*$/).flatten.join("\n")
    assert_match(/body\[data-chat-background="animated"\] \.chat-scroll \{ animation: none; \}/, reduced)
  end

  test "S3: bubbles are opaque in every state (no translucency over the pattern)" do
    assert_no_match(/\.bubble[^{]*\{[^}]*opacity:\s*0\.\d/, css)
    assert_match(/color:\s*var\(--accent-fg\)/, css[/^\.from-user \.bubble\s*\{([^}]*)\}/, 1])
  end
  # Spec 029 fix after the release gate: contrast of the labels the gate measured, computed from the palette tokens.
  def palette(block)
    block.scan(/--([a-z0-9-]+):\s*(#[0-9a-f]{6})/).to_h { |name, hex| [ name, hex[1..].scan(/../).map { |c| c.to_i(16) } ] }
  end

  def mix(a, b, share) = a.zip(b).map { |x, y| x * share + y * (1 - share) }

  def contrast(a, b)
    lum = ->(rgb) { rgb.map { |v| v /= 255.0; v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055)**2.4 }.zip([ 0.2126, 0.7152, 0.0722 ]).sum { |v, w| v * w } }
    hi, lo = [ lum.(a), lum.(b) ].sort.reverse
    (hi + 0.05) / (lo + 0.05)
  end

  test "S3 fix: failed-send error, system and verifier names and code in a failed message reach 4.5:1 in both palettes" do
    light = palette(css[/^:root\s*\{(.*?)^\}/m, 1])
    dark = light.merge(palette(css[/^body\[data-theme="dark"\]\s*\{(.*?)^\}/m, 1]))
    { "light" => light, "dark" => dark }.each do |name, p|
      pairs = {
        "failed text and error" => [ p["bad-text"], p["bad-soft"] ],
        "code in a failed message" => [ p["bad-text"], p["surface"] ],
        "system name" => [ p["warn-text"], p["warn-soft"] ],
        "verifier name" => [ p["ok-text"], mix(p["ok-soft"], p["surface"], 0.55) ]
      }
      pairs.each { |what, (fg, bg)| assert_operator contrast(fg, bg), :>=, 4.5, "#{name}: #{what}" }
    end
    rule = ->(selector) { css[/^#{Regexp.escape(selector)}\s*\{([^}]*)\}/, 1] or flunk "no rule #{selector}" }
    assert_match(/color:\s*var\(--bad-text\)/, rule.(".bubble.is-failed .bubble-time"), "the error does not take the user bubble's time colour")
    assert_match(/background:\s*var\(--surface\)/, rule.(".bubble.is-failed .bubble-text code"))
    assert_match(/color:\s*var\(--warn-text\)/, rule.(".from-system .bubble-name"))
    assert_match(/color:\s*var\(--ok-text\)/, rule.(".from-verifier .bubble-name"))
  end

  test "S3 fix: the header does not clip — the selector gets its own row in narrow chats; a hidden floating chat keeps no room" do
    assert_match(/@container \(max-width: 760px\) \{ \.chat-head \{ flex-wrap: wrap; \} \.chat-head \.chat-bg \{ order: 10; flex-basis: 100%; \} \}/, css)
    assert_match(/body:has\(\.content > \.chat-app, \.director-layout > \.chat-app\):has\(\.chat-dock\.is-open:not\(\.is-voice\)\) \.main \{ margin-right: 0; \}/, css)
  end
end
