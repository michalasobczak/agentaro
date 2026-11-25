# Spec 055, G4: reads opencode's event stream (`opencode run --format json`, one JSON object per line) as it arrives
# and turns it into the same events as ClaudeStream (spec 030): "text", "tool_use" and "tool_result". Checked on
# opencode 2.4.1:
#   step_start; text (part.text); tool_use (part.tool, part.state: status, input, output, error);
#   step_finish (part.tokens: input, output, reasoning, cache.read/write; part.cost); error (error.message).
# The answer is the text of the last step that wrote any (earlier steps' text is the model thinking aloud).
class OpencodeStream
  MAX_EVENTS = ClaudeStream::MAX_EVENTS
  MAX_PAYLOAD = ClaudeStream::MAX_PAYLOAD
  MAX_LINE = ClaudeStream::MAX_LINE
  TOOLS = { "shell" => "Bash", "bash" => "Bash", "write" => "Write", "edit" => "Edit", "patch" => "Edit", "read" => "Read",
            "webfetch" => "WebFetch", "websearch" => "WebSearch", "glob" => "Glob", "grep" => "Grep", "list" => "LS" }.freeze

  attr_reader :events, :usage, :events_cut, :errors

  def initialize(on_text: nil, on_event: nil)
    @on_text, @on_event = on_text, on_event
    @buffer = String.new(encoding: Encoding::BINARY)
    @events = []
    @usage = {}
    @errors = []
    @steps = [ [] ] # the text parts of each step
  end

  def arguments(args) = args # --format json is already among them

  # As CodexStream (fix 2026-11-24): lines are cut from the bytes and decoded whole.
  def feed(chunk)
    @buffer << chunk.b
    while (newline = @buffer.index("\n"))
      line = @buffer.slice!(0..newline).force_encoding(Encoding::UTF_8).scrub("")
      event = parse(line) or next
      read(event)
    end
    @buffer = String.new(encoding: Encoding::BINARY) if @buffer.bytesize > MAX_LINE
  end

  def answer(_stdout)
    feed("\n") unless @buffer.empty? # a last line without its newline
    texts = @steps.reverse.find { |parts| parts.any? { |t| t.strip.present? } }
    texts ? texts.join("\n\n") : "" # only the model's text is an answer, never the raw events
  end

  private

  def read(event)
    part = event["part"].is_a?(Hash) ? event["part"] : {}
    case event["type"]
    when "step_start" then @steps << []
    when "text" then text(part["text"].to_s)
    when "tool_use" then tool(part)
    when "step_finish" then read_usage(part)
    when "error" then failed(event.dig("error", "message") || event["error"].to_s)
    end
  end

  def text(value)
    return if value.empty?

    @steps.last << value
    add("text", text: limit(value))
    @on_text&.call(@steps.last.join("\n\n")) # spec 017: the director's answer so far
  end

  def tool(part)
    state = part["state"].is_a?(Hash) ? part["state"] : {}
    id = (part["callID"] || part["id"]).to_s
    name = TOOLS.fetch(part["tool"].to_s, part["tool"].to_s.presence || "tool")
    add("tool_use", id: id, name: name, input: limit(state["input"].to_json))
    return unless %w[completed error].include?(state["status"])

    add("tool_result", id: id, name: name, source: (name == "Bash" ? "command" : "agent"), error: state["status"] == "error",
                       content: limit(state["output"] || state["error"]))
  end

  def read_usage(part)
    tokens = part["tokens"].is_a?(Hash) ? part["tokens"] : {}
    cache = tokens["cache"].is_a?(Hash) ? tokens["cache"] : {}
    sum = ->(key, value) { @usage[key] = @usage[key].to_i + value.to_i if value }
    sum.(:input_tokens, tokens["input"])
    sum.(:output_tokens, tokens["output"].to_i + tokens["reasoning"].to_i) if tokens.key?("output")
    sum.(:cache_read_tokens, cache["read"])
    sum.(:cache_write_tokens, cache["write"])
    @usage[:cost_usd] = @usage[:cost_usd].to_f + part["cost"].to_f if part.key?("cost")
    @usage[:turns] = @usage[:turns].to_i + 1
  end

  def failed(message)
    @errors << message.to_s.truncate(2000) if @errors.size < 10
    add("text", text: limit("Error: #{message}"))
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
