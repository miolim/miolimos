require "test_helper"

# #1677 (aus immoOS #1658 übernommen) (Hans): „Um die Aktualität von Hilfetext und Anleitung zu
# gewährleisten … Die ID kennzeichnet den Icon-Ort."
class IconMarker1658Test < ActionView::TestCase
  include MarkdownHelper
  include ApplicationHelper

  test "#1658: :icon:<name>: wird zum Symbol" do
    html = render_inline_markdown("Klicke :icon:copy: zum Kopieren.", hilfe_marker: true)
    assert_includes html, "<svg"
    assert_not_includes html, ":icon:copy:"
  end

  test "#1658: :ui:<bedienelement>: zeigt das Icon, das die Funktion heute traegt" do
    html = render_inline_markdown("Klicke :ui:karte_schliessen:, um die Adresse zu kopieren.", hilfe_marker: true)
    assert_includes html, "<svg"
    assert_includes html, I18n.t("shared.close_button.close_card") # als Tooltip
    assert_not_includes html, ":ui:karte_schliessen:"
  end

  # Der Kern der Sache: Wechselt das Icon einer Funktion, wechselt der
  # Hilfetext mit — ohne dass jemand 38 Texte durchsieht.
  test "#1658: ein Icon-Wechsel im Verzeichnis wirkt im Text" do
    vorher = render_inline_markdown(":ui:bearbeiten:", hilfe_marker: true)

    # Dasselbe, was ein Icon-Wechsel im Verzeichnis bewirkt.
    original = UiElemente.method(:icon_fuer)
    begin
      UiElemente.define_singleton_method(:icon_fuer) { |_schluessel| "trash" }
      @icon_vorhanden = nil
      nachher = render_inline_markdown(":ui:bearbeiten:", hilfe_marker: true)
    ensure
      UiElemente.define_singleton_method(:icon_fuer, original)
    end

    assert_not_equal vorher, nachher
    assert_equal vorher, render_inline_markdown(":ui:bearbeiten:", hilfe_marker: true)
  end

  test "#1658: ein Tippfehler bleibt sichtbar stehen" do
    html = render_inline_markdown("Klicke :icon:gibtesnicht: und :ui:auchnicht:.", hilfe_marker: true)
    assert_includes html, ":icon:gibtesnicht:"
    assert_includes html, ":ui:auchnicht:"
  end

  # Der Marker landet im HTML, nachdem der Sanitizer gelaufen ist. Ein Text,
  # der wie ein Marker aussieht, darf trotzdem kein beliebiges HTML einsetzen.
  test "#1658: der Marker kann kein fremdes Markup einschleusen" do
    html = render_inline_markdown(":icon:../../../etc/passwd: :ui:<script>alert(1)</script>:", hilfe_marker: true)
    assert_not_includes html, "<script"
    assert_not_includes html, "passwd</svg>"
  end

  test "#1658: Text ohne Marker bleibt unberuehrt" do
    html = render_inline_markdown("Ein Doppelpunkt: hier passiert nichts.", hilfe_marker: true)
    assert_includes html, "Ein Doppelpunkt: hier passiert nichts."
    assert_not_includes html, "<svg"
  end

  # ── R6: Feld- und Abschnittsbezeichnungen ────────────────────────────

  # Hans: „Felder bitte fett, Bereiche fett und kursiv … zusätzlich fest für
  # beides eine Farbe."
  test "#1658 R6: :feld: setzt die aktuelle Beschriftung fett" do
    html = render_inline_markdown("Tragen Sie es unter :feld:knowledge.editors.relationships.target_placeholder: ein.", hilfe_marker: true)
    assert_includes html, I18n.t("knowledge.editors.relationships.target_placeholder")
    assert_match(%r{<strong class="hilfe-bezeichnung hilfe-feld[^"]*"}, html)
    assert_not_includes html, ":feld:"
  end

  test "#1658 R6: :bereich: setzt sie fett UND kursiv" do
    html = render_inline_markdown("Der Abschnitt :bereich:knowledge.editors.relationships.title: hält die Verbindungen.", hilfe_marker: true)
    assert_match(%r{<strong class="hilfe-bezeichnung hilfe-bereich[^"]*"[^>]*><em>}, html)
    assert_includes html, I18n.t("knowledge.editors.relationships.title")
  end

  # Der eigentliche Zweck: Wird die Beschriftung im Programm geändert, ändert
  # sich der Hilfetext mit — ohne dass jemand ihn anfasst.
  test "#1658 R6: eine umbenannte Beschriftung wirkt sofort im Text" do
    vorher = render_inline_markdown(":feld:knowledge.editors.relationships.target_placeholder:", hilfe_marker: true)
    nachher = I18nBeschriftungen.stub_text("Gesamtwohnfläche") do
      render_inline_markdown(":feld:knowledge.editors.relationships.target_placeholder:", hilfe_marker: true)
    end
    assert_includes nachher, "Gesamtwohnfläche"
    assert_not_equal vorher, nachher
  end

  test "#1658 R6: ein unbekannter Schlüssel bleibt sichtbar stehen" do
    html = render_inline_markdown("Unter :feld:gibt.es.nicht: steht nichts.", hilfe_marker: true)
    assert_includes html, ":feld:gibt.es.nicht:"
  end

  test "#1658 R6: der eingesetzte Text kann kein Markup einschleusen" do
    html = render_inline_markdown(":feld:hilfe.titel:", hilfe_marker: true)
    assert_not_includes html, "<script"
    assert_includes html, I18n.t("hilfe.titel")
  end

  # ── #1677: die beiden bewussten Abweichungen vom Fork ─────────────────

  # Marker gelten NUR in Hilfetexten. In einer Aufgabe oder Antwort bleibt
  # `:ui:xyz:` schlichter Text — dort schreibt man über Doppelpunkte, Uhrzeiten
  # und Code, ohne an die Hilfe zu denken.
  test "#1677: ohne hilfe_marker bleibt ein Marker schlichter Text" do
    html = render_inline_markdown("Klicke :ui:karte_schliessen: zum Schließen.")
    assert_includes html, ":ui:karte_schliessen:"
    assert_not_includes html, "<svg"
  end

  # Ersetzt wird nur in TEXTKNOTEN. Der Fork ersetzte per gsub im fertigen HTML —
  # ein Marker in einem Link-Ziel zerbrach das Markup, einer im Code-Beispiel
  # das Beispiel.
  test "#1677: Marker in Code und in Link-Zielen bleiben unangetastet" do
    html = render_inline_markdown("So schreibt man es: `:icon:check:` — und [Link](https://example.org/:icon:check:/x).",
                                  hilfe_marker: true)
    assert_includes html, "<code>:icon:check:</code>"
    assert_includes html, 'href="https://example.org/:icon:check:/x"'
    assert_not_includes html, "<svg"
  end
end
