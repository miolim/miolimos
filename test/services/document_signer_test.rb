require "test_helper"

# #564: Signier-Strecke (PAdES via pyHanko). Setup ist serverlokal —
# vorhanden auf der Box, anderswo skip. Der Guard wird immer getestet.
class DocumentSignerTest < ActiveSupport::TestCase
  test "sign: wirft klaren Fehler, wenn das Setup fehlt" do
    original = DocumentSigner::KEY
    DocumentSigner.send(:remove_const, :KEY)
    DocumentSigner.const_set(:KEY, "/nonexistent/key.pem")
    err = assert_raises(DocumentSigner::Error) { DocumentSigner.sign("%PDF-fake") }
    assert_match(/Signier-Setup fehlt/, err.message)
  ensure
    DocumentSigner.send(:remove_const, :KEY)
    DocumentSigner.const_set(:KEY, original)
  end

  test "sign: signiert ein echtes PDF (PAdES, ByteRange vorhanden)" do
    skip "Signier-Setup nicht vorhanden" unless DocumentSigner.available?
    skip "Chrome nicht vorhanden" unless system("which", DocumentPdf::CHROME,
                                                out: File::NULL, err: File::NULL)
    pdf = DocumentPdf.render("<!doctype html><html><body><p>Signier-Test</p></body></html>")
    signed = DocumentSigner.sign(pdf, reason: "Test #564")
    assert signed.start_with?("%PDF-"), "kein PDF-Magic"
    assert signed.bytesize > pdf.bytesize, "Signatur hat nichts hinzugefügt"
    assert_includes signed, "ByteRange", "keine PAdES-Signaturstruktur (ByteRange)"
  end
end
