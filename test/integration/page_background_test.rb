require "test_helper"

# Spec 028: animated page background. CSS only, so this checks the contract in the stylesheet and that
# application pages carry the hook (body[data-theme]) while the sign-in layout and the chat surface do not use it.
class PageBackgroundTest < ActionDispatch::IntegrationTest
  CSS = Rails.root.join("app/assets/stylesheets/application.css")

  def css = File.read(CSS)

  def block(selector, source = css)
    source[/^#{Regexp.escape(selector)}\s*\{([^}]*)\}/m, 1] or flunk "no rule for #{selector}"
  end

  test "application pages carry the background hook; the sign-in layout does not" do
    get new_session_path
    assert_select "body.auth"
    assert_select "body[data-theme]", 0
    sign_in(create_user)
    [ root_path, calendar_path, spaces_path ].each do |path|
      get path
      assert_select "body[data-theme]", 1, path
      assert_select "link[rel=stylesheet][href*=app]", { minimum: 1 }, path
    end
  end

  test "G3, R3: one decorative layer behind the content that never takes clicks" do
    layer = block("body[data-theme]::before")
    assert_match(/content:\s*"";/, layer)
    assert_match(/position:\s*fixed/, layer)
    assert_match(/z-index:\s*-1/, layer)
    assert_match(/pointer-events:\s*none/, layer)
    assert_match(/animation:\s*page-drift\s/, layer)
    assert_match(/isolation:\s*isolate/, block("body[data-theme]"))
    assert_equal 1, css.scan(/^body\[data-theme\]::before\s*\{/).size, "one layer only"
  end

  test "S4, R2: the animation moves only transform or opacity" do
    frames = css[/@keyframes page-drift\s*\{(.*?)\}\s*\}/m, 1] or flunk "no page-drift keyframes"
    properties = frames.scan(/([a-z-]+)\s*:/).flatten.uniq
    assert_equal [ "transform" ], properties - [ "opacity" ]
    refute_match(/background-position|filter|blur/, block("body[data-theme]::before"))
  end

  test "G2: reduced motion stops the background" do
    reduce = css.scan(/@media \(prefers-reduced-motion: reduce\)\s*\{([^{}]*\{[^}]*\})\s*\}/m).flatten
    rule = reduce.find { |r| r.include?("body[data-theme]::before") } or flunk "no reduced-motion rule for the background"
    assert_match(/animation:\s*none/, rule)
  end

  test "G2, R1: light and dark palettes for the page glow" do
    assert_match(/--page-glow-1:\s*rgba\(99, 102, 241, 0\.08\)/, block(":root"))
    dark = css.scan(/--page-glow-1:\s*rgba\(139, 133, 255, 0\.12\)/).size
    assert_equal 2, dark, "dark by hand and dark by the system (Auto)"
  end

  test "R4: the chat keeps its own opaque surface" do
    assert_match(/background:\s*var\(--bg\)/, block(".chat-scroll"))
    refute_match(/\.chat-scroll[^{]*\{[^}]*page-glow/m, css)
  end
end
