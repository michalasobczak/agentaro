require "test_helper"

# Fix 2026-11-24: steps failed with "ArgumentError: invalid byte sequence in UTF-8" (9 runs on 2026-11-23 and 24).
# The tool's output is read in 16 KB chunks; when a chunk ended inside a Polish letter (two bytes in UTF-8), the
# buffer held half a character and matching a line in it raised. A line is complete only at "\n", which never falls
# inside a character, so lines are cut from the bytes and decoded whole.
class StreamUtf8Test < ActiveSupport::TestCase
  def split_inside_a_letter(text)
    bytes = text.b
    at = bytes.index("ł".b) + 1 # between the two bytes of "ł"
    [ bytes.byteslice(0, at), bytes.byteslice(at..) ]
  end

  test "Claude Code: a chunk that ends inside a letter does not break the stream; the text arrives whole" do
    texts = []
    stream = ClaudeStream.new(->(t) { texts << t })
    line = { type: "stream_event", event: { delta: { type: "text_delta", text: "Zapisałem plik storage.py" } } }.to_json + "\n"
    result = { type: "result", result: "Gotowe: zmieniłem ocenę na 0–3." }.to_json + "\n"
    split_inside_a_letter(line).each { |chunk| stream.feed(chunk) }
    split_inside_a_letter(result).each { |chunk| stream.feed(chunk) }
    assert_equal "Zapisałem plik storage.py", texts.last
    assert_equal "Gotowe: zmieniłem ocenę na 0–3.", stream.answer("")
  end

  test "Codex: a chunk that ends inside a letter does not break the stream" do
    stream = CodexStream.new
    line = { type: "item.completed", item: { id: "1", type: "agent_message", text: "Zmieniłem storage.py" } }.to_json + "\n"
    split_inside_a_letter(line).each { |chunk| stream.feed(chunk) }
    assert_equal "Zmieniłem storage.py", stream.answer("")
  end

  test "a line with bytes that are not UTF-8 at all is read with them dropped, not raised" do
    stream = CodexStream.new
    line = "{\"type\":\"item.completed\",\"item\":{\"id\":\"1\",\"type\":\"agent_message\",\"text\":\"zle \xFF bajty\"}}\n".b
    stream.feed(line)
    assert_equal "zle  bajty", stream.answer("")
  end
end
