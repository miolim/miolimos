# #532 Phase 2 (Hans, 2026-06-07): HTML → PDF über Headless-Chrome (auf der
# Box vorhanden, kein Gem nötig). Das HTML muss selbst-enthalten sein (Theme
# inline), damit Chrome ohne Asset-Server rendert. Honoriert @page/Print-CSS,
# also stimmen Seitenränder/-umbrüche genau.
class DocumentPdf
  class Error < StandardError; end

  CHROME = ENV.fetch("CHROME_BIN", "google-chrome")
  MM_PER_INCH = 25.4
  # #564: harte Obergrenze für den Chrome-Prozess — ein hängender Render darf
  # keinen Puma-Worker dauerhaft blockieren. coreutils-timeout killt nach
  # Ablauf (Exit 124), set-vorhanden auf der Box.
  TIMEOUT_SECONDS = ENV.fetch("DOCPDF_TIMEOUT", "60")

  # Einfacher Render über die Chrome-CLI (--print-to-pdf), ohne Kopf-/Fußzeile.
  # Für Rechnung/Brief/ZUGFeRD: die DIN-Geometrie steckt komplett im @page/CSS.
  def self.render(html)
    Dir.mktmpdir("docpdf") do |dir|
      in_file  = File.join(dir, "doc.html")
      out_file = File.join(dir, "doc.pdf")
      File.write(in_file, html)
      ok = system("timeout", TIMEOUT_SECONDS,
                  CHROME, "--headless=new", "--no-sandbox", "--disable-gpu",
                  "--no-pdf-header-footer", "--user-data-dir=#{dir}/profile",
                  "--print-to-pdf=#{out_file}", "file://#{in_file}",
                  out: File::NULL, err: File::NULL)
      unless ok && File.exist?(out_file)
        timed_out = $?.exitstatus == 124
        raise Error, timed_out ? "Chrome-Render Timeout (#{TIMEOUT_SECONDS}s)" : "Chrome-Render fehlgeschlagen"
      end
      File.binread(out_file)
    end
  end

  # #562 (Hans): mehrseitiger Render MIT echten Seitenrändern (oben/unten/links/
  # rechts in mm) und einer Fußzeile auf JEDER Seite (Seitenzahl + Dokument-ID).
  # Die CLI kann keine eigene Fußzeile setzen — daher Headless-Chrome via CDP
  # (Ferrum). `footer_html` ist ein Chrome-Footer-Template (font-size INLINE
  # nötig; nutzbare Klassen: pageNumber/totalPages/title/date/url).
  def self.render_paged(html, footer_html: nil,
                        margin_mm: { top: 22, bottom: 18, left: 25, right: 20 })
    Dir.mktmpdir("docpdf") do |dir|
      in_file = File.join(dir, "doc.html")
      File.write(in_file, html)
      browser = Ferrum::Browser.new(
        headless: true, browser_path: CHROME,
        browser_options: { "no-sandbox" => nil, "disable-gpu" => nil },
        process_timeout: 30, timeout: 30, save_path: dir
      )
      begin
        page = browser.create_page
        page.go_to("file://#{in_file}")
        opts = {
          format: :A4, landscape: false, print_background: true,
          prefer_css_page_size: false,
          margin_top:    margin_mm[:top].to_f    / MM_PER_INCH,
          margin_bottom: margin_mm[:bottom].to_f / MM_PER_INCH,
          margin_left:   margin_mm[:left].to_f   / MM_PER_INCH,
          margin_right:  margin_mm[:right].to_f  / MM_PER_INCH,
          encoding: :binary
        }
        if footer_html
          opts[:display_header_footer] = true
          opts[:header_template] = "<div></div>"     # leerer Kopf (kein Default)
          opts[:footer_template] = footer_html
        end
        page.pdf(**opts)
      ensure
        browser.quit
      end
    end
  rescue Ferrum::Error, StandardError => e
    raise Error, "Ferrum-Render fehlgeschlagen: #{e.message}"
  end
end
