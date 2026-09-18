# #1660 (Hans): Token-Verbrauch der Agenten-Sitzungen — verdichtet je Tag,
# Projekt, Aufgabe und Modell. Befüllt wird das von AgentUsage::Import aus den
# Sitzungsprotokollen; angezeigt in Einstellungen → Token-Verbrauch.
#
# Warum überhaupt: Hans arbeitet mit einem Abo und wollte wissen, was eine
# tokenbasierte Abrechnung kosten würde. Gemessen 09/2026: der Löwenanteil
# entfällt nicht auf die Ausgabe, sondern aufs WIEDERLESEN des Kontexts —
# jede Antwort liest den ganzen bisherigen Verlauf erneut.
class AgentUsage < ApplicationRecord
  # Listenpreise in USD je Million Token. Cache-Schreiben ist der Satz für
  # den 1-Stunden-Cache (den nutzt Claude Code; in unseren Protokollen zu
  # 100 %), Cache-Lesen der ermäßigte Satz.
  #
  # Die Sätze sind bewusst hier und nicht in der Datenbank: Sie ändern sich
  # selten, und eine Änderung soll nachvollziehbar im Code stehen. Über
  # ENV lässt sich jeder Satz überschreiben, ohne Deploy-Zwang.
  PREISE_USD = {
    /opus/i   => { ein: 15.0, cache_schreiben: 30.0,  cache_lesen: 1.50, aus: 75.0 },
    /sonnet/i => { ein: 3.0,  cache_schreiben: 6.0,   cache_lesen: 0.30, aus: 15.0 },
    /haiku/i  => { ein: 1.0,  cache_schreiben: 2.0,   cache_lesen: 0.10, aus: 5.0 }
  }.freeze

  UNBEKANNT = { ein: 0.0, cache_schreiben: 0.0, cache_lesen: 0.0, aus: 0.0 }.freeze

  ARTEN = %i[ein cache_schreiben cache_lesen aus].freeze

  validates :tag, :projekt, :model, presence: true

  scope :seit, ->(datum) { where("tag >= ?", datum) }

  # ENV-Override: AGENT_USAGE_PREIS_OPUS_AUS=60 setzt den Ausgabesatz für
  # Opus. Schlüssel: AGENT_USAGE_PREIS_<FAMILIE>_<ART>.
  def self.preise_fuer(model)
    familie, saetze = PREISE_USD.find { |re, _| model.to_s.match?(re) }
    return UNBEKANNT unless saetze
    name = familie.source.delete("\\").upcase
    saetze.to_h do |art, wert|
      [art, ENV.fetch("AGENT_USAGE_PREIS_#{name}_#{art.to_s.upcase}", wert).to_f]
    end
  end

  def self.usd_eur_rate = Llm::ChatClient::USD_EUR_RATE

  # Kosten je Token-Art für eine Menge Zeilen (oder eine einzelne).
  # Rückgabe: { ein:, cache_schreiben:, cache_lesen:, aus:, gesamt: } in USD.
  def self.kosten_usd(zeilen)
    Array(zeilen).each_with_object(Hash.new(0.0)) do |z, summe|
      p = preise_fuer(z.model)
      summe[:ein]             += z.input_tokens          * p[:ein]             / 1_000_000.0
      summe[:cache_schreiben] += z.cache_creation_tokens * p[:cache_schreiben] / 1_000_000.0
      summe[:cache_lesen]     += z.cache_read_tokens     * p[:cache_lesen]     / 1_000_000.0
      summe[:aus]             += z.output_tokens         * p[:aus]             / 1_000_000.0
      summe[:gesamt]          = summe[:ein] + summe[:cache_schreiben] + summe[:cache_lesen] + summe[:aus]
    end
  end

  # Tokensummen + Kosten für eine Menge Zeilen — die Bausteine jeder
  # Tabellenzeile in der Übersicht.
  def self.summe(zeilen)
    zeilen = Array(zeilen)
    {
      antworten:       zeilen.sum(&:antworten),
      ein:             zeilen.sum(&:input_tokens),
      cache_schreiben: zeilen.sum(&:cache_creation_tokens),
      cache_lesen:     zeilen.sum(&:cache_read_tokens),
      aus:             zeilen.sum(&:output_tokens),
      kosten:          kosten_usd(zeilen)
    }
  end

  def kosten_usd = self.class.kosten_usd([self])[:gesamt]
  def kosten_eur = kosten_usd * self.class.usd_eur_rate
end
