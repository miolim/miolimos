require "test_helper"

# #536 P4: der Export muss 1:1 enthalten, was der eingeloggte Kunde sah —
# und NICHTS darüber hinaus (Isolation + Sichtbarkeits-Flags gelten auch hier).
class PortalExporterTest < ActiveSupport::TestCase
  setup do
    @hans   = create_human
    @topic  = Topic.create!(name: "Export-Projekt", slug: "ex-#{SecureRandom.hex(3)}", creator: @hans)
    @fremd  = Topic.create!(name: "Fremd-Projekt", slug: "fr-#{SecureRandom.hex(3)}", creator: @hans)

    @ms = Task.create!(title: "Export-Meilenstein", creator: @hans, status: :open,
                       client_milestone: true, due_date: Date.new(2026, 8, 1),
                       skip_default_assignee: true)
    TaskTopic.create!(task: @ms, topic: @topic, position: 1)
    intern = Task.create!(title: "Interner-Schritt", creator: @hans, status: :open,
                          skip_default_assignee: true)
    TaskTopic.create!(task: intern, topic: @topic, position: 2)

    doc = Document.create!(kind: :brief, status: :final, topic_id: @topic.id, subject: "Konzept")
    @art = doc.document_artifacts.create!(pdf: "%PDF-export", creator: @hans, shared_with_client: true)
    doc.document_artifacts.create!(pdf: "%PDF-geheim", creator: @hans)

    msg = PortalMessage.create!(direction: :inbound, subject: "Portal", body: "Kundennachricht-Export",
                                sent_at: Time.current, portal_visible: true,
                                external_id: "pm-#{SecureRandom.hex(4)}")
    CommunicationTopic.create!(communication: msg, topic: @topic)
    hidden = PortalMessage.create!(direction: :inbound, subject: "Portal", body: "Versteckte-Notiz",
                                   sent_at: Time.current, portal_visible: false,
                                   external_id: "pm-#{SecureRandom.hex(4)}")
    CommunicationTopic.create!(communication: hidden, topic: @topic)

    ms_fremd = Task.create!(title: "Fremd-Meilenstein", creator: @hans, status: :open,
                            client_milestone: true, skip_default_assignee: true)
    TaskTopic.create!(task: ms_fremd, topic: @fremd, position: 1)
  end

  test "render_pages: enthält genau die Kundensicht (inkl. Kommunikation + Termine)" do
    pages = PortalExporter.new(@topic).render_pages

    assert_equal %w[index.html roadmap.html termine.html dokumente.html nachrichten.html].sort,
                 pages.keys.sort

    assert_includes pages["roadmap.html"], "Export-Meilenstein"
    refute_includes pages["roadmap.html"], "Interner-Schritt"
    refute_includes pages["roadmap.html"], "Fremd-Meilenstein"

    assert_includes pages["termine.html"], "1. August 2026"
    assert_includes pages["nachrichten.html"], "Kundennachricht-Export"
    refute_includes pages["nachrichten.html"], "Versteckte-Notiz"
    # Export = Archiv: kein Formular, keine Session-Elemente.
    refute_includes pages["nachrichten.html"], "<textarea"
    refute_includes pages["index.html"], "Abmelden"
    assert_includes pages["index.html"], "Projektabschluss-Archiv"

    # Links sind relativ (statischer Host), nicht App-Pfade.
    assert_includes pages["index.html"], 'href="roadmap.html"'
    refute_includes pages["roadmap.html"], "/portal/"
  end

  test "zip: Seiten + freigegebene PDFs, ungeteilte fehlen" do
    bytes = PortalExporter.zip(@topic)
    entries = {}
    Zip::InputStream.open(StringIO.new(bytes)) do |io|
      while (e = io.get_next_entry)
        entries[e.name] = io.read
      end
    end
    assert_includes entries.keys, "index.html"
    pdfs = entries.keys.select { |k| k.start_with?("dokumente/") }
    assert_equal 1, pdfs.size, "genau das freigegebene PDF"
    assert_equal "%PDF-export", entries[pdfs.first]
    # Die Dokumente-Seite verlinkt exakt diese Datei relativ.
    assert_includes entries["dokumente.html"], %(href="#{pdfs.first}")
  end
end
