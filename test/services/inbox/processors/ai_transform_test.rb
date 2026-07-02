require "test_helper"

# #203: Coverage fuer den AI-Transform-Processor. LLM-Aufruf wird
# gestubbt, damit der Test ohne API-Key laeuft und deterministisch ist.
class Inbox::Processors::AiTransformTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    grant(@hans, "Source",        %w[read create update delete])
    @template = PromptTemplate.create!(slug: "summary-#{SecureRandom.hex(2)}",
                                        name: "Zusammenfassung",
                                        prompt_text: "Fasse zusammen: {{input}}",
                                        creator: @hans)
    @proc = Inbox::Processors::AiTransform.new
  end

  test "applies? immer true (User waehlt explizit)" do
    item = InboxItem.create!(creator: @hans, source_kind: "text",
                              raw_content: "hi", status: "pending")
    assert Inbox::Processors::AiTransform.applies?(item)
  end

  test "process! wirft, wenn kein PromptTemplate gewaehlt" do
    item = InboxItem.create!(creator: @hans, source_kind: "text",
                              raw_content: "Hallo", status: "pending",
                              payload: {})
    err = assert_raises(RuntimeError) { @proc.process!(item, actor: @hans) }
    assert_match(/Kein PromptTemplate/, err.message)
  end

  test "process! wirft, wenn LLM leeren String liefert" do
    item = InboxItem.create!(creator: @hans, source_kind: "text",
                              raw_content: "Lange Eingabe", status: "pending",
                              payload: { "prompt_template_slug" => @template.slug })
    stub_chat_client("") do
      err = assert_raises(RuntimeError) { @proc.process!(item, actor: @hans) }
      assert_match(/leere Antwort/, err.message)
    end
  end

  test "process! erzeugt abstract-KI mit LLM-Output und Tags" do
    item = InboxItem.create!(creator: @hans, source_kind: "text",
                              raw_content: "Lange Eingabe", status: "pending",
                              payload: { "prompt_template_slug" => @template.slug })
    output = "# Mein Titel\n\nFazit blah."
    stub_chat_client(output) do
      @proc.process!(item, actor: @hans)
    end
    ki = KnowledgeItem.find_by(title: "Mein Titel")
    assert ki, "abstract-KI muss angelegt sein"
    assert_equal "abstract", ki.item_type
    assert_includes ki.tags, "ai-summary"
    assert_includes ki.tags, @template.slug
  end

  test "process! ohne h1-Header verwendet Template-Name + Item-Title" do
    item = InboxItem.create!(creator: @hans, source_kind: "text", title: "Mein Inbox-Item",
                              raw_content: "Eingabe", status: "pending",
                              payload: { "prompt_template_slug" => @template.slug })
    stub_chat_client("Antwort ohne h1") do
      @proc.process!(item, actor: @hans)
    end
    ki = KnowledgeItem.find_by(title: "Zusammenfassung: Mein Inbox-Item")
    assert ki, "Fallback-Title muss aus Template.name + item.title gebildet werden"
  end

  test "render_prompt ersetzt {{var}}-Platzhalter" do
    out = @proc.send(:render_prompt, "X={{input}}, Y={{source_url}}",
                       input: "ein", source_url: "https://e.de", source_title: "T")
    assert_equal "X=ein, Y=https://e.de", out
  end

  test "derive_title nimmt h1 wenn vorhanden, sonst Fallback" do
    item = InboxItem.create!(creator: @hans, source_kind: "text", title: "X",
                              status: "pending", payload: {})
    assert_equal "Echter Titel",
                 @proc.send(:derive_title, "# Echter Titel\n\nbody", @template, item)
    assert_equal "Zusammenfassung: X",
                 @proc.send(:derive_title, "ohne h1", @template, item)
  end

  # #705 (b): output_format=html → render_mode=html-KI.
  test "process! mit output_format=html erzeugt render_mode=html-KI" do
    @template.update!(output_format: "html")
    item = InboxItem.create!(creator: @hans, source_kind: "text",
                              raw_content: "Eingabe", status: "pending",
                              payload: { "prompt_template_slug" => @template.slug })
    output = "<!DOCTYPE html><html><head><title>HTML-Titel</title></head>" \
             "<body><h1>Hi</h1></body></html>"
    stub_chat_client(output) do
      @proc.process!(item, actor: @hans)
    end
    ki = KnowledgeItem.find_by(title: "HTML-Titel")
    assert ki, "KI mit Titel aus <title> muss angelegt sein"
    assert ki.render_html?, "render_mode muss html sein"
    assert_includes ki.tags, "html"
    assert_includes ki.body, "<h1>Hi</h1>"
  end

  test "system_prompt unterscheidet markdown und html" do
    assert_match(/Markdown/, @proc.send(:system_prompt, @template))
    @template.update!(output_format: "html")
    assert_match(/HTML/, @proc.send(:system_prompt, @template))
  end
end
