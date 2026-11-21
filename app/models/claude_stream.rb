# Spec 017: reads Claude Code's stream-json output as it arrives. Text deltas are joined and passed to on_text;
# the final answer is the "result" line (or the joined text when that line is missing, or the plain output when
# nothing was streamed).
# Spec 030, G2/G3: every Claude Code call streams; the tool calls and their results (truncated), the assistant's
# texts, and the usage and cost of the result line are kept for the run's trace. Every chunk is read, also beyond the
# output limit, so the result line is never lost behind large tool results.
class ClaudeStream
  MAX_EVENTS = 1000
  MAX_PAYLOAD = 8 * 1024      # spec 030, Q1: bytes kept of each tool call, tool result or text
  MAX_LINE = 4 * 1024 * 1024 # a line longer than this is skipped, not buffered
  # R3: where a tool's result comes from, so later specs never take outside content as the user's words.
  SOURCES = { "WebFetch" => "web", "WebSearch" => "web", "Read" => "file", "Grep" => "file", "Glob" => "file", "LS" => "file",
              "Bash" => "command", "Edit" => "agent", "Write" => "agent", "MultiEdit" => "agent", "NotebookEdit" => "agent",
              "TodoWrite" => "agent", "Task" => "agent", "Agent" => "agent" }.freeze

  attr_reader :events, :usage, :events_cut

  # on_event (spec 038): called with each event as it is kept, for the live log.
  def initialize(on_text = nil, on_event: nil)
    @on_text = on_text
    @on_event = on_event
    @buffer = +""
    @text = +""
    @assistant_text = +""
    @events = []
    @tools = {}
    @usage = {}
    @result = nil
  end

  # The print-mode arguments with streamed JSON instead of plain text; partial messages only when someone reads them.
  def arguments(args)
    i = args.index("--output-format") or return args
    extra = @on_text ? [ "--verbose", "--include-partial-messages" ] : [ "--verbose" ]
    args.dup.tap { |a| a[i + 1] = "stream-json" }.insert(i + 2, *extra)
  end

  def feed(chunk)
    @buffer << chunk.dup.force_encoding(Encoding::UTF_8)
    while (line = @buffer.slice!(/\A[^\n]*\n/))
      event = parse(line) or next
      read(event)
    end
    @buffer = +"" if @buffer.bytesize > MAX_LINE
  end

  def answer(stdout)
    result = @result || stdout.to_s.dup.force_encoding(Encoding::UTF_8).scrub("").lines.reverse_each.lazy.map { |l| parse(l) }.find { |e| e && e["type"] == "result" }
    return result["result"] if result && result["result"].is_a?(String)

    @text.presence || @assistant_text.presence || stdout.to_s # no stream events at all: plain output, as without streaming
  end

  private

  def read(event)
    case event["type"]
    when "stream_event"
      delta = event.dig("event", "delta")
      return unless delta.is_a?(Hash) && delta["type"] == "text_delta"

      @text << delta["text"].to_s
      @on_text&.call(@text)
    when "assistant" then blocks(event).each { |block| assistant_block(block) }
    when "user" then blocks(event).each { |block| tool_result(block) }
    when "result" then result(event)
    end
  end

  def blocks(event)
    content = event.dig("message", "content")
    content.is_a?(Array) ? content.grep(Hash) : []
  end

  def assistant_block(block)
    case block["type"]
    when "text"
      @assistant_text << block["text"].to_s
      add("text", text: limit(block["text"]))
    when "tool_use"
      @tools[block["id"]] = block["name"].to_s
      add("tool_use", id: block["id"].to_s, name: block["name"].to_s, input: limit(block["input"].to_json))
    end
  end

  def tool_result(block)
    return unless block["type"] == "tool_result"

    name = @tools[block["tool_use_id"]]
    content = block["content"]
    text = content.is_a?(Array) ? content.grep(Hash).map { |c| c["text"] || "[#{c["type"]}]" }.join("\n") : content.to_s
    add("tool_result", id: block["tool_use_id"].to_s, name: name, source: SOURCES.fetch(name.to_s, "other"),
                       error: block["is_error"] == true, content: limit(text))
  end

  def result(event)
    @result = event
    usage = event["usage"].is_a?(Hash) ? event["usage"] : {}
    @usage = { input_tokens: usage["input_tokens"], output_tokens: usage["output_tokens"],
               cache_read_tokens: usage["cache_read_input_tokens"], cache_write_tokens: usage["cache_creation_input_tokens"],
               cost_usd: event["total_cost_usd"], turns: event["num_turns"] }.compact
  end

  def add(kind, **data)
    return @events_cut = true if @events.size >= MAX_EVENTS

    event = { "kind" => kind, **data.compact.transform_keys(&:to_s) }
    @events << event
    @on_event&.call(event)
  end

  def limit(value)
    text = value.to_s
    text.bytesize > MAX_PAYLOAD ? text.byteslice(0, MAX_PAYLOAD).scrub("") + "\n[… cut at #{MAX_PAYLOAD / 1024} KB]" : text
  end

  def parse(line)
    line = line.strip
    line.start_with?("{") ? JSON.parse(line) : nil
  rescue JSON::ParserError
    nil
  end
end
