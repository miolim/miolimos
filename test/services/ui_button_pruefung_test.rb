require "test_helper"

# #1669: Die Erkennung hat in immoOS zweimal danebengelegen — beide Male fiel
# es erst beim Umbauen auf, nicht im Test. Hier sind die Fälle, an denen sie
# sich messen lassen muss.
class UiButtonPruefungTest < ActiveSupport::TestCase
  def offen(quelle) = UiButtonPruefung.offene_stellen(quelle)

  test "ein Knopf mit bloßem Symbol fehlt im Katalog" do
    quelle = %(<button type="button" title="x"><%= icon "pencil" %></button>)
    assert_equal [1], offen(quelle)
  end

  test "ein Aufklapper mit bloßem Symbol ebenso" do
    quelle = %(<summary class="a"><%= icon "plus_circle" %></summary>)
    assert_equal [1], offen(quelle)
  end

  # Fehler 1: ERB wurde beim Textvergleich pauschal weggeworfen — ein Knopf mit
  # übersetzter Beschriftung galt als namenlos.
  test "ein Knopf mit übersetzter Beschriftung braucht keine Kennung" do
    quelle = %(<button><%= icon "upload" %><span><%= t("a.b") %></span></button>)
    assert_empty offen(quelle)
  end

  test "ein Knopf mit reinem Text braucht keine Kennung" do
    quelle = %(<button><%= icon "x" %> Schließen</button>)
    assert_empty offen(quelle)
  end

  test "eine Kennung am Knopf genügt" do
    quelle = %(<button data-ui-icon="blade_close"><%= icon "x" %></button>)
    assert_empty offen(quelle)
  end

  test "der Schlüssel der Beschriftung genügt ebenfalls" do
    quelle = %(<button data-i18n-key="knowledge_items.tabs.body"><%= icon "file" %></button>)
    assert_empty offen(quelle)
  end

  test "ein Knopf, der seinen Marker selbst nennt, braucht keinen Katalogeintrag" do
    quelle = %(<button data-marker=":icon:pencil:"><%= icon "pencil" %></button>)
    assert_empty offen(quelle)
  end

  test "auch ui_icon im Inhalt zählt als registriert" do
    quelle = %(<button><%= ui_icon :blade_close %></button>)
    assert_empty offen(quelle)
  end

  # `data-action="click->x#y"` trägt selbst ein `>`; eine naive Attribut-Regex
  # endet dort und zählt den Knopf falsch.
  test "ein Pfeil im data-action verwirrt die Erkennung nicht" do
    quelle = %(<button data-action="click->blade-stack#closeCard"><%= icon "x" %></button>)
    assert_equal [1], offen(quelle)
  end

  test "ein Knopf ohne Symbol und ohne Zeichen ist nie ein Fall" do
    quelle = %(<button type="submit">Speichern</button>)
    assert_empty offen(quelle)
  end

  test "die Zeilennummer stimmt" do
    quelle = "<div>\n  <p>x</p>\n  <button><%= icon \"pencil\" %></button>\n</div>"
    assert_equal [3], offen(quelle)
  end

  # ── #1669 (Hans: „Bitte checken."): die geschärfte Grenze ────────────────
  #
  # Die immoOS-Grenze hieß „ohne sichtbaren Text". In miolimOS tragen 37 Knöpfe
  # als ganze Beschriftung ein ZEICHEN — allein 27 identische `×` für „Zeile
  # entfernen". Die haben keinen Namen; ihr Symbol ist nur mit einem
  # Schriftzeichen gemalt statt mit einer Bilddatei.

  test "ein Knopf, dessen ganze Beschriftung ein Zeichen ist, hat keinen Namen" do
    assert_equal [1], offen(%(<button type="button" class="p-1">×</button>))
    assert_equal [1], offen(%(<button>+</button>))
    assert_equal [1], offen(%(<summary>›</summary>))
  end

  test "auch beim Zeichen-Knopf befreit eine Kennung" do
    assert_empty offen(%(<button data-ui-icon="zeile_entfernen">×</button>))
  end

  # Bewusste Grenze: eine Ziffer ist ein WERT, kein Zeichen-Symbol. Im Zweifel
  # sammelt die Prüfung nichts ein.
  test "eine Ziffer als Beschriftung gilt als Name" do
    assert_empty offen(%(<button>0</button>))
  end

  test "ein leerer Knopf ohne Symbol ist kein Fall" do
    assert_empty offen(%(<button class="x"></button>))
  end

  # `button_to "×"` erzeugt den Knopf erst zur Laufzeit — in der
  # `<button>`-Suche ist er unsichtbar.
  test "auch button_to mit Zeichen-Beschriftung wird gefunden" do
    quelle = %(<%= button_to "×", topic_path(t), method: :delete %>)
    assert_equal [1], offen(quelle)
  end

  test "button_to mit echter Beschriftung nicht" do
    quelle = %(<%= button_to t("actions.save"), topic_path(t) %>)
    assert_empty offen(quelle)
  end
end
