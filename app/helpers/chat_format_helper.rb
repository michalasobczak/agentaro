# Owner fix ("model zwraca formatowanie **xxx**, ale czat tego nie formatuje"): a small, safe part of Markdown in chat
# messages — **bold**, *italic*, `code`, "- " and "1. " lists, "# " headings — built from tags whose text is escaped;
# nothing from the message is ever inserted as HTML. chat.js (chatFormat) draws the same structure with textContent.
module ChatFormatHelper
  LIST_ITEM = /\A\s*(?:([-*•])|(\d+)[.)])\s+(.*)\z/
  HEADING = /\A\s{0,3}\#{1,6}\s+(.*)\z/
  INLINE = /\*\*(.+?)\*\*|__(.+?)__|`([^`\n]+)`|(?<![\w*])\*(?=\S)(.+?)(?<=\S)\*(?![\w*])/

  def chat_text(content)
    safe_join(chat_blocks(content.to_s).map do |kind, value|
      case kind
      when :heading then tag.div(chat_inline(value), class: "md-h")
      when :ul then tag.ul(safe_join(value.map { |item| tag.li(chat_inline(item)) }))
      when :ol then tag.ol(safe_join(value.map { |item| tag.li(chat_inline(item)) }))
      else tag.div(chat_inline(value), class: "md-p")
      end
    end)
  end

  private

  # [[kind, value]]: paragraphs (lines kept), headings, and runs of list items.
  def chat_blocks(text)
    blocks = []
    text.split("\n").each do |line|
      if (m = line.match(LIST_ITEM))
        kind = m[1] ? :ul : :ol
        if blocks.last&.first == kind then blocks.last.last << m[3] else blocks << [ kind, [ m[3] ] ] end
      elsif (m = line.match(HEADING))
        blocks << [ :heading, m[1] ]
      elsif line.strip.empty?
        blocks << [ :gap, nil ]
      elsif blocks.last&.first == :p
        blocks.last[1] = "#{blocks.last[1]}\n#{line}"
      else
        blocks << [ :p, line ]
      end
    end
    blocks.reject { |kind, _| kind == :gap }
  end

  def chat_inline(text)
    parts = []
    rest = text
    while (m = rest.match(INLINE))
      parts << m.pre_match
      parts << if m[1] || m[2] then tag.strong(m[1] || m[2]) elsif m[3] then tag.code(m[3]) else tag.em(m[4]) end
      rest = m.post_match
    end
    safe_join(parts << rest)
  end
end
