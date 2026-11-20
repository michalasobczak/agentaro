# Spec 017, R4: the director's reply while it is being written, kept in this process's memory only (the scheduler
# runs inside the web server), keyed by the chat run. Never stored in the database or logs; cleared at the end.
module ReplyStream
  @texts = Concurrent::Map.new

  module_function

  # reply_to: the user message the reply is written for (owner fix: an outdated reply is never spoken).
  def write(run_id, text, reply_to: nil) = @texts[run_id] = [ text, reply_to ]
  def read(run_id) = @texts[run_id]&.first
  def reply_to(run_id) = @texts[run_id]&.last
  def clear(run_id) = @texts.delete(run_id)

  # The "reply" text so far from a partial JSON answer like {"reply": "Hello, I wi — decoded, unfinished escapes
  # dropped. Empty until the reply has started.
  def partial_reply(text)
    start = text =~ /"reply"\s*:\s*"/ or return ""
    i = start + Regexp.last_match(0).length
    out = +""
    while i < text.length
      char = text[i]
      return out if char == '"'

      if char == "\\"
        escape = text[i + 1] or return out
        case escape
        when "n" then out << "\n"
        when "t" then out << "\t"
        when "r", "b", "f" then nil
        when "u"
          hex = text[i + 2, 4]
          return out unless hex&.match?(/\A\h{4}\z/)

          out << [ hex.to_i(16) ].pack("U") rescue nil
          i += 4
        else out << escape
        end
        i += 2
      else
        out << char
        i += 1
      end
    end
    out
  end
end
