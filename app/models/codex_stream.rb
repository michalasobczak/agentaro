# Spec 038, G6: reads Codex's event stream (`codex exec --json`, one JSON object per line) as it arrives and turns it
# into the same events as ClaudeStream (spec 030): "text", "tool_use" and "tool_result". Checked on codex-cli 0.170.0:
#   item.started / item.completed with item.type command_execution (command, aggregated_output, exit_code),
#   file_change (changes: path, kind), web_search (query), mcp_tool_call (server, tool), agent_message (text);
#   turn.completed with usage; turn.failed and error with a message.
# The answer itself is still Codex's last message (its -o file); the events go to the live log and the trace.
class CodexStream
  MAX_EVENTS = ClaudeStream::MAX_EVENTS
  MAX_PAYLOAD = ClaudeStream::MAX_PAYLOAD
  MAX_LINE = ClaudeStream::MAX_LINE

  attr_reader :events, :usage, :events_cut, :errors # errors: spec 043, what Codex reported as failing

  def initialize(on_event: nil)
    @on_event = on_event
    @buffer = +""
    @events = []
    @usage = {}
    @started = {}
    @messages = []
    @errors = []
  end

  # The exec arguments with the event stream on (before the prompt's "-").
  def arguments(args)
    i = args.index("exec") or return args
    args.dup.insert(i + 1, "--json")
  end

  def feed(chunk)
    @buffer << chunk.dup.force_encoding(Encoding::UTF_8)
    while (line = @buffer.slice!(/\A[^\n]*\n/))
      event = parse(line) or next
      read(event)
    end
    @buffer = +"" if @buffer.bytesize > MAX_LINE
  end

  # Used only when Codex wrote no last-message file: its last message from the stream.
  def answer(stdout) = @messages.last || stdout.to_s

  private

  def read(event)
    case event["type"]
    when "item.started" then started(event["item"])
    when "item.completed" then completed(event["item"])
    when "turn.completed" then read_usage(event["usage"])
    when "turn.failed" then failed(event.dig("error", "message"))
    when "error" then failed(event["message"])
    end
  end

  def failed(message)
    @errors << message.to_s.truncate(2000) if @errors.size < 10
    add("text", text: limit("Error: #{message}"))
  end

  def started(item)
    return unless item.is_a?(Hash) && !@started.key?(item["id"])

    use = tool_use(item) or return
    @started[item["id"]] = true
    add("tool_use", **use)
  end

  def completed(item)
    return unless item.is_a?(Hash)

    if item["type"] == "agent_message"
      @messages << item["text"].to_s
      return add("text", text: limit(item["text"]))
    end
    started(item) # an item reported only when done still shows what was done
    case item["type"]
    when "command_execution"
      add("tool_result", id: item["id"].to_s, name: "Bash", source: "command", error: !item["exit_code"].to_i.zero?, content: limit(item["aggregated_output"]))
    when "file_change"
      add("tool_result", id: item["id"].to_s, name: "Edit", source: "agent", error: item["status"] == "failed", content: item["status"].to_s)
    when "mcp_tool_call"
      add("tool_result", id: item["id"].to_s, name: "mcp", source: "other", error: item["status"] == "failed", content: limit(item["result"].to_json))
    end
  end

  def tool_use(item)
    name, input = case item["type"]
                  when "command_execution" then [ "Bash", { command: item["command"] } ]
                  when "file_change" then [ "Edit", { changes: Array(item["changes"]).grep(Hash).map { |c| "#{c["kind"]} #{c["path"]}" } } ]
                  when "web_search" then [ "WebSearch", { query: item["query"] } ]
                  when "mcp_tool_call" then [ "mcp", { tool: [ item["server"], item["tool"] ].compact.join("/") } ]
                  else return
                  end
    { id: item["id"].to_s, name: name, input: limit(input.to_json) }
  end

  def read_usage(data)
    return unless data.is_a?(Hash)

    @usage = { input_tokens: data["input_tokens"], output_tokens: data["output_tokens"], cache_read_tokens: data["cached_input_tokens"] }.compact
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
