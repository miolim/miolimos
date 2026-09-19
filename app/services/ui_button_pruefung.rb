# #1669 (Übergabe aus immoOS #1664): Die Voraussetzung für einen namenlosen
# Knopf ist der Helfer `ui_button` — ohne Katalogeintrag entsteht keiner. Diese
# Klasse schließt die Hintertür: Sie findet Knöpfe und Aufklapper, die trotzdem
# roh gebaut wurden.
#
# Warum als Klasse und nicht als Handvoll Zeilen im Test: Die Erkennung hat in
# immoOS zweimal danebengelegen, und beide Male fiel es erst beim Umbauen auf —
#   1. ERB wurde beim Textvergleich pauschal weggeworfen, also galt ein Knopf
#      mit `<%= t("…") %>` als beschriftungslos;
#   2. das Abräumen der HTML-Tags (`<[^>]+>`) traf auch `<%= … %>`, weil ein
#      ERB-Tag mit `<` beginnt und mit `>` endet.
# Eine Prüfung, die selbst geprüft werden kann, war die Lehre daraus
# (test/services/ui_button_pruefung_test.rb).
class UiButtonPruefung
  ERB_PLATZHALTER = " ERB ".freeze

  # [Zeilennummer, …] der Knöpfe ohne Kennung in dieser Quelle.
  def self.offene_stellen(quelle)
    (rohe_stellen(quelle) + offene_button_to(quelle)).uniq.sort
  end

  def self.rohe_stellen(quelle)
    quelle.enum_for(:scan, /<(button|summary)\b/).filter_map do
      m = Regexp.last_match
      art = m[1]
      ende = tag_ende(quelle, m.end(0))
      next if ende.negative?

      attribute = quelle[m.begin(0)...ende]
      schluss = quelle.index("</#{art}>", ende)
      next unless schluss

      inhalt = quelle[(ende + 1)...schluss]
      next unless ohne_namen?(attribute, inhalt)

      quelle[0...m.begin(0)].count("\n") + 1
    end
  end

  # Was den Knopf ansprechbar macht — und damit vom Katalog befreit:
  #   data-ui-icon   die Kennung selbst (ui_button/ui_icon)
  #   data-i18n-key  der Schlüssel seiner Beschriftung (so lösen es Reiter,
  #                  deren Name nur im Tooltip steht)
  #   data-marker    der Knopf SAGT, welchen Marker er meint — so eine
  #                  Symbol-Auswahl, die aus jedem Symbol des Programms einen
  #                  Knopf macht. Ein Eintrag je Symbol wäre dort sinnlos:
  #                  Die Liste IST der Katalog.
  ANSPRECHBAR = %w[data-ui-icon data-i18n-key data-marker].freeze

  # #1669 (Hans: „Ich weiß nicht, ob das … stimmt und sinnvoll ist. Bitte
  # checken."): Die immoOS-Grenze hieß „ohne sichtbaren Text". Gemessen an
  # miolimOS ist das zu eng gefasst — 37 Knöpfe tragen als ganze Beschriftung
  # ein ZEICHEN (`×` 27×, `+`, `›`, `←`, `→`, `¶`). Die haben keinen Namen; ihr
  # Symbol ist nur mit einem Schriftzeichen gemalt statt mit einer Bilddatei.
  # Allein 27 identische `×` für „Zeile entfernen" in 21 Dateien — dieselbe
  # Lage wie die 14 identischen Plus-Symbole, die den Anstoß gaben.
  #
  # Die Frage ist deshalb nicht „steht da sichtbarer Text?", sondern
  # „steht da ein NAME?": Buchstaben oder Ziffern. Ein Knopf, der `0` zeigt,
  # bleibt bewusst draußen — das ist ein Wert, kein Zeichen-Symbol, und die
  # Grenze soll im Zweifel nichts einsammeln.
  def self.ohne_namen?(attribute, inhalt)
    return false if ANSPRECHBAR.any? { |a| attribute.include?(a) } || inhalt.include?("ui_icon")

    rest = beschriftungsrest(inhalt)

    if inhalt.match?(/icon[\s(]/)
      # Bild-Symbol: Bleibt neben ihm Text oder eine andere ERB-Ausgabe übrig,
      # trägt der Knopf seinen Namen selbst.
      rest.empty?
    else
      # Kein Bild-Symbol: ein Zeichen als ganze Beschriftung ist auch keiner.
      !rest.empty? && !rest.match?(/[[:alnum:]]/)
    end
  end

  # Bestandsname aus der Zeit, als nur Bild-Symbole zählten.
  singleton_class.send(:alias_method, :nur_symbol?, :ohne_namen?)

  # Die Symbol-Ausgabe heraus, den REST ansehen.
  def self.beschriftungsrest(inhalt)
    rest = inhalt.gsub(/<%=[^%]*\bicon[^%]*%>/m, "")
    # ERB in Sicherheit bringen, BEVOR die HTML-Tags fallen — sonst räumt der
    # Tag-Filter `<%= t("…") %>` gleich mit weg (Fehler 2 oben). Der
    # Platzhalter trägt Buchstaben: Bleibt irgendeine ERB-Ausgabe übrig, ist
    # der Knopf damit beschriftet.
    rest = rest.gsub(/<%.*?%>/m, ERB_PLATZHALTER)
    rest.gsub(/<[^>]+>/, "").gsub(/&\w+;/, "").strip
  end

  # #1669: `button_to "×"` erzeugt den Knopf erst zur Laufzeit — in der
  # `<button>`-Suche oben ist er unsichtbar. Ein Zeichen als Beschriftung ist
  # hier genauso namenlos wie dort.
  def self.offene_button_to(quelle)
    quelle.enum_for(:scan, /button_to\s+(["'])([^"'[:alnum:]\s]{1,2})\1/).map do
      quelle[0...Regexp.last_match.begin(0)].count("\n") + 1
    end
  end

  # Erstes `>` außerhalb von Anführungszeichen — `data-action="click->x#y"`
  # enthält selbst ein `>`, eine naive Regex zählt daran vorbei.
  def self.tag_ende(quelle, ab)
    i = ab
    zitat = nil
    while i < quelle.length
      zeichen = quelle[i]
      if zitat
        zitat = nil if zeichen == zitat
      elsif ['"', "'"].include?(zeichen)
        zitat = zeichen
      elsif zeichen == ">"
        return i
      end
      i += 1
    end
    -1
  end
end
