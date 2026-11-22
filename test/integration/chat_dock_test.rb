require "test_helper"

# Spec 020, R4 (owner fix 2026-11-21): a maximized floating chat must not cover the page the user goes to. The rule
# lives in chat.js (the floating chat keeps its state in the browser); it was checked in the browser at 1440 px:
# maximized on Team, a click on Brain in the menu showed Brain beside the chat in its side panel.
class ChatDockTest < ActionDispatch::IntegrationTest
  test "R4: a click on a link outside the chat brings a maximized chat back to the side panel" do
    js = Rails.root.join("app/assets/javascripts/chat.js").read
    handler = js[/document\.addEventListener\("turbo:click", \(event\) => \{.*?\n  \}\);/m]
    assert handler, "chat.js listens to Turbo link clicks"
    # Spec 042: the decision moved to dockAfterClick() (tested in test/javascript/dock_test.rb); on a computer an
    # outside click on a maximized chat gives "unmax", and the chat closes only on a phone.
    assert_match 'max: dock.classList.contains("is-max")', handler
    assert_match 'inside: !!event.target.closest("[data-chat-dock]")', handler, "links inside the chat keep it maximized"
    assert_match 'else if (next === "unmax") setMax(false);', handler, "back to the side panel (and remembered so)"
    assert_match "const phone = window.matchMedia?.(PHONE_QUERY).matches === true;", handler, "the chat closes only on a phone"
  end
end
