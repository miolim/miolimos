require "test_helper"

# #941: das Verfahren (#926) direkt testen — Verzweigung plain/paged nach
# den Modell-Hooks + archive! (PDF → optional Signatur → Artefakt).
# DocumentPdf/DocumentSigner werden gestubbt (kein Chrome/venv nötig).
class DocumentRendererTest < ActiveSupport::TestCase
  def stub_singleton(mod, name, impl)
    original = mod.method(name)
    mod.define_singleton_method(name, impl)
    yield
  ensure
    mod.singleton_class.send(:remove_method, name) rescue nil
    mod.define_singleton_method(name, original) if original
  end

  test "pdf: Brief nutzt den CLI-Render, NDA den paged-Render mit Fußzeile" do
    calls = []
    stub_singleton(DocumentPdf, :render, ->(html) { calls << [:render]; "PLAIN" }) do
      stub_singleton(DocumentPdf, :render_paged, ->(html, footer_html: nil, **) { calls << [:paged, footer_html]; "PAGED" }) do
        brief = Document.new(kind: :brief)
        nda   = Document.new(kind: :nda, created_at: Time.current)
        assert_equal "PLAIN", DocumentRenderer.pdf(brief, "<html/>")
        assert_equal "PAGED", DocumentRenderer.pdf(nda, "<html/>")
      end
    end
    assert_equal :render, calls[0][0]
    assert_equal :paged,  calls[1][0]
    assert_includes calls[1][1], "_NDA", "NDA-Fußzeile muss die Dokument-ID tragen"
    assert_includes calls[1][1], "pageNumber"
  end

  test "pdf: Invoice (print_paged? false) nutzt den CLI-Render" do
    stub_singleton(DocumentPdf, :render, ->(html) { "PLAIN" }) do
      assert_equal "PLAIN", DocumentRenderer.pdf(Invoice.new(kind: :rechnung), "<html/>")
    end
  end

  test "archive!: legt Artefakt an; signiert nur, wenn das Setup da ist" do
    hans = create_human
    doc  = Document.create!(kind: :brief, status: :final)
    stub_singleton(DocumentPdf, :render, ->(html) { "PDFBYTES" }) do
      stub_singleton(DocumentSigner, :available?, -> { false }) do
        art = DocumentRenderer.archive!(doc, "<html/>", creator: hans)
        assert_equal "PDFBYTES", art.pdf
        refute art.signed
        assert_equal "Document", art.printable_type
      end
      stub_singleton(DocumentSigner, :available?, -> { true }) do
        stub_singleton(DocumentSigner, :sign, ->(bytes, reason:) { "SIGNED:#{bytes}" }) do
          art = DocumentRenderer.archive!(doc, "<html/>", creator: hans)
          assert art.signed
          assert_equal "SIGNED:PDFBYTES", art.pdf
        end
      end
    end
    assert_equal 2, doc.document_artifacts.count
  end
end
