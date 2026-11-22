require "test_helper"
require "open3"
require "tmpdir"

# Spec 042: what a page change started by a click does to the floating chat. The real dockAfterClick() from chat.js
# runs in JavaScriptCore (jsc, part of macOS), like the voice tests (spec 035).
class DockTest < ActiveSupport::TestCase
  JSC = ENV.fetch("AGENTARO_JSC", "/System/Library/Frameworks/JavaScriptCore.framework/Versions/Current/Helpers/jsc")

  def self.rule_source
    lines = Rails.root.join("app/assets/javascripts/chat.js").read.lines
    first = lines.index("  function dockAfterClick({ phone, open, max, inside }) {\n") or raise "dockAfterClick() not found in chat.js"
    last = (first...lines.size).find { |i| lines[i] == "  }\n" } or raise "end of dockAfterClick() not found"
    lines[first..last].join
  end

  def decide(**state)
    skip "JavaScriptCore (jsc) not found at #{JSC}; set AGENTARO_JSC" unless File.executable?(JSC)
    Dir.mktmpdir do |dir|
      script = File.join(dir, "dock.js")
      File.write(script, "#{self.class.rule_source}\nprint(dockAfterClick(#{state.to_json}));\n")
      output, status = Open3.capture2e(JSC, script)
      assert status.success?, output
      output.strip
    end
  end

  test "G1: on a phone an open chat closes when a menu item outside it is chosen" do
    assert_equal "close", decide(phone: true, open: true, max: false, inside: false)
  end

  test "G2: on a phone a link inside the chat closes it too, so the page can be seen" do
    assert_equal "close", decide(phone: true, open: true, max: true, inside: true)
  end

  test "negative: on a computer an open chat stays open; a maximized one goes back to the side panel" do
    assert_equal "keep", decide(phone: false, open: true, max: false, inside: false)
    assert_equal "unmax", decide(phone: false, open: true, max: true, inside: false)
    assert_equal "keep", decide(phone: false, open: true, max: true, inside: true)
  end

  test "a closed chat on a phone stays closed" do
    assert_equal "keep", decide(phone: true, open: false, max: false, inside: false)
  end
end
