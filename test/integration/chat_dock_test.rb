require "test_helper"

# Spec 020, R4 (owner fix 2026-11-21): a maximized floating chat must not cover the page the user goes to. The rule
# lives in chat.js (the floating chat keeps its state in the browser); it was checked in the browser at 1440 px:
# maximized on Team, a click on Brain in the menu showed Brain beside the chat in its side panel.
class ChatDockTest < ActionDispatch::IntegrationTest
  test "R4: a click on a link outside the chat brings a maximized chat back to the side panel" do
    js = Rails.root.join("app/assets/javascripts/chat.js").read
    handler = js[/document\.addEventListener\("turbo:click", \(event\) => \{.*?\n  \}\);/m]
    assert handler, "chat.js listens to Turbo link clicks"
    assert_match 'dock.classList.contains("is-max")', handler, "only a maximized chat changes"
    assert_match '!event.target.closest("[data-chat-dock]")', handler, "links inside the chat keep it maximized"
    assert_match "setMax(false)", handler, "back to the side panel (and remembered so)"
    assert_no_match(/setOpen\(false/, handler, "the chat stays open")
  end
end
