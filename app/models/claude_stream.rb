# Spec 017: reads Claude Code's stream-json output as it arrives. Text deltas are joined and passed to on_text;
# the final answer is the "result" line (or the joined text when that line is missing, or the plain output when
# nothing was streamed).
class ClaudeStream
  def initialize(on_text)
    @on_text = on_text
    @buffer = +""
    @text = +""
  end

  # The print-mode arguments with streamed JSON instead of plain text.
  def arguments(args)
    i = args.index("--output-format") or return args
    args.dup.tap { |a| a[i + 1] = "stream-json" }.insert(i + 2, "--verbose", "--include-partial-messages")
  end

  def feed(chunk)
    @buffer << chunk.dup.force_encoding(Encoding::UTF_8)
    while (line = @buffer.slice!(/\A[^\n]*\n/))
      event = parse(line) or next
      delta = event["type"] == "stream_event" ? event.dig("event", "delta") : nil # not a modifier if: the loop keeps locals
      next unless delta.is_a?(Hash) && delta["type"] == "text_delta"

      @text << delta["text"].to_s
      @on_text.call(@text)
    end
  end

  def answer(stdout)
    result = stdout.to_s.dup.force_encoding(Encoding::UTF_8).scrub("").lines.reverse_each.lazy.map { |l| parse(l) }.find { |e| e && e["type"] == "result" }
    return result["result"] if result && result["result"].is_a?(String)

    @text.presence || stdout.to_s # no stream events at all: plain output, as without streaming
  end

  private

  def parse(line)
    line = line.strip
    line.start_with?("{") ? JSON.parse(line) : nil
  rescue JSON::ParserError
    nil
  end
end
