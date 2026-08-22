require "test_helper"

# #1453 (Hans): „Dazuschreiben, dass das für alles gelten soll."
#
# Die Höhe einer Blade-Stack-Seite ist Fensterhöhe minus Topbar. Sie steht in
# `.stack-page` (application.css) und NICHT in den Templates.
#
# Warum das einen Test wert ist: Vorher stand die Zahl siebzehnmal wortgleich
# in Templates. Im immoOS-Fork sind daraus zwei Werte geworden — neun Seiten
# tragen `5rem`, weil sie später und einzeln dazukamen. Als der mobile
# Spine-Fehler dort auf einer dieser Seiten gemessen wurde, geriet die
# Abweichung in eine Regel, die für ALLE Seiten gilt, und beim Herüberholen
# nach miolimOS stimmte sie nicht mehr.
#
# Dieser Test ist die Sicherung dagegen — und er wandert beim nächsten Merge
# in den Fork mit. Dort wird er zunächst ROT: genau die neun Seiten, die
# auseinandergelaufen sind. Das ist beabsichtigt. Ein roter Test beim Merge
# ist die billigste Art, eine Abweichung zu melden; die teure Art ist, dass
# sie jemandem auf dem Telefon auffällt.
class StackPageClassTest < ActiveSupport::TestCase
  VIEWS = Rails.root.join("app/views")

  # `_split_pane` ist ausgenommen: Dort begrenzt dieselbe Zahl die HÖHE EINER
  # SPALTE (max-h), nicht die einer Stapel-Seite. Andere Sache, gleiche Zahl —
  # wenn sie je gemeinsam gepflegt werden soll, gehört sie an dieselbe
  # Variable, aber das ist ein eigener Schnitt.
  AUSNAHMEN = %w[shared/_split_pane.html.erb].freeze

  test "keine Stapel-Seite wiederholt die Höhe im Template" do
    treffer = Dir.glob(VIEWS.join("**", "*.erb")).filter_map do |pfad|
      rel = Pathname.new(pfad).relative_path_from(VIEWS).to_s
      next if AUSNAHMEN.include?(rel)

      zeilen = File.readlines(pfad).each_with_index.filter_map do |zeile, i|
        "#{rel}:#{i + 1}" if zeile.include?("h-[calc(100dvh-")
      end
      zeilen.presence
    end.flatten

    assert_empty treffer, <<~HINWEIS
      Diese Templates schreiben die Seitenhöhe selbst hin statt `class="stack-page"`
      zu verwenden:

        #{treffer.join("\n        ")}

      Die Höhe steht in `.stack-page` (app/assets/tailwind/application.css).
      Wird sie im Template wiederholt, laufen die Werte auseinander — genau das
      ist im immoOS-Fork passiert.
    HINWEIS
  end

  test "die Stapel-Seiten benutzen die Klasse auch wirklich" do
    # Nur SEITEN-Templates. Ein Partial (`_name.html.erb`) bringt seinen
    # Seiten-Wrapper nicht selbst mit — den setzt, wer es rendert.
    seiten = Dir.glob(VIEWS.join("**", "*.erb")).select do |pfad|
      next false if File.basename(pfad).start_with?("_")
      File.read(pfad).include?('data-blade-stack-target="container"')
    end
    assert_operator seiten.size, :>=, 15, "es gibt mehrere Stapel-Seiten"

    ohne_klasse = seiten.reject { |pfad| File.read(pfad).include?('class="stack-page"') }
    assert_empty ohne_klasse.map { |p| Pathname.new(p).relative_path_from(VIEWS).to_s },
                 "jede Seite mit einem Stapel-Container trägt `stack-page`"
  end
end
