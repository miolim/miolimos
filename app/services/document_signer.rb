require "tmpdir"

# #547 (Hans, 2026-06-08): AES-Signatur (PAdES) auf ein gerendertes Dokument-
# PDF. Shellt zum isolierten Signier-venv (pyHanko) + dem Signier-Skript im
# Repo. Zertifikat/Schlüssel liegen serverlokal (Geheimnis, nicht im Repo) in
# SIGN_DIR. Selbst-verwaltetes Zertifikat = fortgeschrittene Signatur (AES):
# eindeutig zugeordnet + manipulationssicher; Vertrauen via Cert-Verteilung.
# Für QES (Schriftform) druckt Hans aus und unterschreibt händisch.
class DocumentSigner
  class Error < StandardError; end

  PYTHON   = ENV.fetch("SIGN_PYTHON", File.expand_path("~/.venvs/miolimos-sign/bin/python"))
  SIGN_DIR = ENV.fetch("SIGN_DIR",    File.expand_path("~/miolimos_signing"))
  SCRIPT   = Rails.root.join("lib/python/sign_pdf.py").to_s
  KEY      = File.join(SIGN_DIR, "key.pem")
  CERT     = File.join(SIGN_DIR, "cert.pem")

  # Ist das Signier-Setup vorhanden (venv + Skript + Zertifikat/Schlüssel)?
  def self.available?
    [PYTHON, SCRIPT, KEY, CERT].all? { |p| File.exist?(p) }
  end

  # Signiert die übergebenen PDF-Bytes und liefert die signierten Bytes.
  def self.sign(pdf_bytes, reason: "Elektronisch signiert (AES)")
    raise Error, "Signier-Setup fehlt (venv/Zertifikat)" unless available?
    Dir.mktmpdir("docsign") do |dir|
      inp  = File.join(dir, "in.pdf")
      outp = File.join(dir, "out.pdf")
      File.binwrite(inp, pdf_bytes)
      # #564: coreutils-timeout — hängendes pyHanko darf keinen Worker blockieren.
      ok = system("timeout", "30", PYTHON, SCRIPT, KEY, CERT, inp, outp, reason.to_s,
                  out: File::NULL, err: File::NULL)
      unless ok && File.exist?(outp) && File.size(outp).positive?
        raise Error, $?.exitstatus == 124 ? "Signieren Timeout (30s)" : "Signieren fehlgeschlagen"
      end
      File.binread(outp)
    end
  end
end
