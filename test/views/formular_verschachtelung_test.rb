require "test_helper"

# immoOS #1537 (Hans: „Bitte prüfen.") — Auskopplung aus #1409 und #1536.
#
# Ein `button_to` IST im HTML ein Formular. Steht es in einem `form_with`, gibt
# es das nicht: Der Browser verwirft beim Parsen das innere `<form>`-Start-Tag
# samt seiner Adresse und hängt dessen Inhalt an das ÄUSSERE Formular. Was das
# anrichtet, hängt davon ab, was drinsteht:
#
#   #1409  Ein verstecktes `_method=delete` wanderte mit — „9 Positionen
#          übernehmen" ging als DELETE raus, lief ins 404, Turbo meldete
#          „Content missing", die Übernahme fand nie statt.
#   #1537  Zwei Knöpfe im Bestätigen-Formular des Dokument-Imports wurden zu
#          dessen Submit-Knöpfen. Weil das Formular `confirm_import=1` führt,
#          hätte „Verwerfen" den Beleg ANGELEGT statt ihn zu verwerfen.
#
# Beide Male lautlos: kein Fehler im Log, keine rote Seite, nur ein Knopf, der
# etwas anderes tut, als er verspricht. Deshalb wird hier nicht ein einzelner
# Fall geprüft, sondern der ganze Bestand.
#
# Geprüft wird die ERB-BLOCKSTRUKTUR, nicht die Einrückung: `… do %>` und
# `<% if %>` öffnen, `<% end %>` schließt. Ein reiner Textvergleich („steht ein
# button_to hinter einem form_with?") ginge daneben, sobald das Formular vorher
# geschlossen wurde — und genau das ist der Normalfall.
class FormularVerschachtelungTest < ActiveSupport::TestCase
  WURZEL      = Rails.root.join("app/views")
  FORMULAR    = /\bform_with\b|\bform_tag\b|\bbutton_to\b/
  BLOCK_ENDE  = /\bdo\b(\s*\|[^|]*\|)?\s*\z/
  BLOCK_START = /\A\s*(if|unless|case|begin|while|until|for)\b/

  # Renders innerhalb eines Formulars, deren Ziel erst zur Laufzeit feststeht
  # (`render details_partial`). Die kann kein Scanner auflösen — sie sind von
  # Hand geprüft: `details_partial` kennt fünf Werte (form_details_abstract /
  # _transcript / _quote / _person / _organization), keiner enthält ein
  # Formular. Der Eintrag steht hier, damit ein NEUER dynamischer Render im
  # Formular diesen Test rot macht, statt still in den blinden Fleck zu fallen.
  DYNAMISCH_GEPRUEFT = ["knowledge_items/_stack_new_card.html.erb"].freeze

  # Eine Datei: was erzeugt sie an Formularen, was steckt worin?
  class Sicht
    attr_reader :kurz, :verschachtelt, :renders_im_formular, :erzeugt_formular

    def initialize(pfad)
      @kurz = pfad.relative_path_from(WURZEL).to_s
      @verschachtelt = []
      @renders_im_formular = []
      @erzeugt_formular = false
      lies(pfad.read)
    end

    private

    def lies(text)
      stapel = []
      zeile  = 1
      pos    = 0
      while (start = text.index("<%", pos))
        zeile += text[pos...start].count("\n")
        ende = text.index("%>", start) or break
        roh = text[(start + 2)...ende]
        tag(roh, zeile, stapel) unless roh.start_with?("#")
        zeile += roh.count("\n")
        pos = ende + 2
      end
      @erzeugt_formular ||= text.include?("<form")
    end

    def tag(roh, zeile, stapel)
      code = roh.sub(/\A[=-]+/, "").strip
      return stapel.pop if code.match?(/\Aend\s*-?\z/)

      formular = code.match?(FORMULAR)
      @erzeugt_formular ||= formular
      offen = stapel.reverse.find { |(art, _, _)| art == :formular }

      @verschachtelt << [zeile, knapp(code), knapp(offen[2])] if formular && offen
      if offen && code.match?(/\brender\b/)
        @renders_im_formular << [zeile, code[/render\s*\(?\s*(?:partial:\s*)?["']([^"']+)["']/, 1]]
      end

      stapel << [formular ? :formular : :block, zeile, code] if code.match?(BLOCK_ENDE) || code.match?(BLOCK_START)
    end

    def knapp(code) = code.gsub(/\s+/, " ")[0, 80]
  end

  def sichten
    @sichten ||= Dir.glob(WURZEL.join("**/*.erb")).sort.map { |p| Sicht.new(Pathname.new(p)) }
  end

  def nach_name = @nach_name ||= sichten.to_h { |s| [s.kurz, s] }

  # "bank_ledgers/blade_card" → "bank_ledgers/_blade_card.html.erb";
  # "positions" → relativ zum Verzeichnis der rendernden Datei.
  def ziel(name, quelle)
    stamm =
      if name.include?("/")
        teile = name.split("/")
        "#{teile[0..-2].join('/')}/_#{teile[-1]}"
      else
        "#{File.dirname(quelle.kurz)}/_#{name}"
      end
    %w[html.erb turbo_stream.erb].filter_map { |e| nach_name["#{stamm}.#{e}"] }.first
  end

  test "#1537: kein Formular steht in einem anderen Formular" do
    funde = sichten.flat_map do |s|
      s.verschachtelt.map { |(zeile, innen, aussen)| "#{s.kurz}:#{zeile}\n    innen : #{innen}\n    aussen: #{aussen}" }
    end
    assert_empty funde, "Formular im Formular — der Browser wirft das innere weg " \
                        "und hängt seinen Inhalt an das äußere:\n  #{funde.join("\n  ")}"
  end

  # Der zweite Weg in dieselbe Falle führt über Dateigrenzen: Das Formular steht
  # in einem Partial, das seinerseits in einem Formular gerendert wird. Im
  # Einzelfall sieht dann jede Datei für sich harmlos aus.
  test "#1537: kein Partial mit Formular wird in einem Formular gerendert" do
    funde = sichten.flat_map do |s|
      s.renders_im_formular.filter_map do |(zeile, name)|
        z = (ziel(name, s) if name)
        "#{s.kurz}:#{zeile} rendert #{z.kurz}" if z&.erzeugt_formular
      end
    end
    assert_empty funde, "Partial mit Formular, gerendert IN einem Formular:\n  #{funde.join("\n  ")}"
  end

  # Die Prüfung bewacht ihren eigenen blinden Fleck: Ein Render mit dynamischem
  # Namen lässt sich nicht auflösen. Wer einen neuen in ein Formular setzt, muss
  # von Hand nachsehen und ihn hier eintragen — sonst gälte die Datei als
  # geprüft, ohne es zu sein.
  test "#1537: dynamische Renders im Formular bleiben namentlich bekannt" do
    dynamisch = sichten.select { |s| s.renders_im_formular.any? { |(_, name)| name.nil? } }.map(&:kurz)
    assert_equal DYNAMISCH_GEPRUEFT.sort, dynamisch.sort,
                 "Ein Render im Formular, dessen Ziel erst zur Laufzeit feststeht, ist neu oder " \
                 "weggefallen. Neue von Hand prüfen und in DYNAMISCH_GEPRUEFT eintragen."
  end

  # Formulare aus Helfern sähe dieser Scanner nicht — er liest nur Views.
  # Solange kein Helfer eines erzeugt, ist das keine Lücke; ändert sich das,
  # sagt es dieser Test.
  test "#1537: kein Helfer erzeugt Formulare" do
    treffer = Dir.glob(Rails.root.join("app/helpers/**/*.rb")).select do |p|
      File.read(p).match?(FORMULAR)
    end
    assert_empty treffer.map { |p| Pathname.new(p).relative_path_from(Rails.root).to_s },
                 "Ein Helfer erzeugt ein Formular — die View-Prüfung sieht das nicht. " \
                 "Entweder den Helfer meiden oder die Prüfung erweitern."
  end
end
