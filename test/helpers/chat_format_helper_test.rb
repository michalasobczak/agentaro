require "test_helper"

# Owner fix ("model zwraca formatowanie **xxx**, ale czat tego nie formatuje"): a safe part of Markdown in the chat.
class ChatFormatHelperTest < ActionView::TestCase
  include ChatFormatHelper

  def html(text) = chat_text(text).to_s

  test "bold, italic and code inside a paragraph; lines kept" do
    assert_equal %(<div class="md-p">Status: <strong>w toku</strong>, <em>teraz</em> i <code>bin/start</code>\ndruga linia</div>),
                 html("Status: **w toku**, *teraz* i `bin/start`\ndruga linia")
  end

  test "lists, numbered lists and headings become blocks; blank lines separate paragraphs" do
    assert_equal %(<div class="md-h">Nomystria</div><ul><li><strong>Research</strong>: running</li><li>Raport: planned</li></ul>) +
                 %(<ol><li>pierwszy</li><li>drugi</li></ol><div class="md-p">Koniec.</div>),
                 html("## Nomystria\n- **Research**: running\n* Raport: planned\n1. pierwszy\n2) drugi\n\nKoniec.")
  end

  test "nothing from the message becomes HTML; lone stars and multiplication stay text" do
    assert_equal %(<div class="md-p">&lt;script&gt;alert(1)&lt;/script&gt; <strong>&lt;b&gt;x&lt;/b&gt;</strong></div>), html("<script>alert(1)</script> **<b>x</b>**")
    assert_equal %(<div class="md-p">2 * 3 * 4 and a*b*c</div>), html("2 * 3 * 4 and a*b*c")
  end
end
