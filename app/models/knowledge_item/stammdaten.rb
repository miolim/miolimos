# #1675 (R2): DIE Liste der skalaren Stammdaten-Felder von Personen und
# Organisationen — Spalte an knowledge_items, gleichnamiger Frontmatter-Key.
#
# Vorher stand jedes Feld einzeln an neun Stellen in sieben Dateien:
# Frontmatter.build (Signatur + Zeile), Reader, Writer#update (Signatur,
# Weitergabe, DB-Update), KnowledgeIndexer, EntityMerge, KnowledgeItemUpdateForm
# und der Anlege-Pfad im Controller. Dreimal in zwei Monaten ergänzt (#1090,
# #1168, #1615) — und eine vergessene Stelle heißt STILLER Datenverlust: Der
# Wert fehlt im Export, der nächste Indexer-Lauf oder Merge räumt ihn ab.
#
# Ein neues Feld ist jetzt: Migration + eine Zeile hier (+ Eingabefeld in der
# View). test/services/stammdaten_rundreise_test.rb prüft die ganze Reise für
# jedes Feld und verlangt für jede neue Spalte eine Entscheidung.
#
# NICHT hier: parent_org und logo (Verweise, die über Titel/UUID aufgelöst
# werden), issuer/vat_exempt/personally_known (Flags mit eigener Semantik),
# aliases/tags (Listen).
class KnowledgeItem
  module Stammdaten
    # name:    Spalte und Frontmatter-Key
    # gueltig: optionaler Katalog-Prüfer — alles andere (auch "") räumt das Feld ab
    # typ:     an welchem item_type das Feld beim ANLEGEN angenommen wird
    #          (nil = kein typgebundenes Anlege-Feld)
    # index:   liest der KnowledgeIndexer das Feld aus der Datei zurück?
    Feld = Struct.new(:name, :gueltig, :typ, :index, keyword_init: true) do
      def key = name.to_s

      # Der Wert, wie er in Frontmatter und Datenbank stehen darf: leer → nil,
      # bei Katalogfeldern nur Katalogwerte.
      def bereinigt(wert)
        wert = wert.presence
        return nil if wert.nil?
        gueltig.nil? || gueltig.call(wert) ? wert : nil
      end
    end

    # Die Reihenfolge ist die der Keys im exportierten Frontmatter — nicht
    # umsortieren, sonst ändert sich jede Personen-Datei beim nächsten Speichern.
    FELDER = [
      Feld.new(name: :first_name,     index: true),
      Feld.new(name: :last_name,      index: true),
      # #516. Der Indexer liest die ORCID bewusst NICHT zurück (Bestand): Sie wird
      # auch an der Datei vorbei gesetzt; ein Rücklesen räumte sie dort ab.
      Feld.new(name: :orcid,          index: false),
      # #1057 (aus immoos #1031): Rechtsform — nur Katalogwerte.
      Feld.new(name: :legal_form,     index: true, typ: "organization", gueltig: ->(w) { LegalForms.valid?(w) }),
      # #1090: Geschlecht nur als Katalogwert; die Anrede ist bewusst Freitext.
      Feld.new(name: :gender,         index: true, typ: "person", gueltig: ->(w) { Salutations.valid_gender?(w) }),
      Feld.new(name: :salutation,     index: true, typ: "person"),
      Feld.new(name: :academic_title, index: true, typ: "person"),
      # #1615: Geburtsname, Freitext.
      Feld.new(name: :birth_name,     index: true, typ: "person")
    ].freeze

    NAMEN = FELDER.map(&:name).freeze

    module_function

    # Trennt aus beliebigen Keyword-Args die Stammdaten heraus.
    def aus(args) = args.slice(*NAMEN)

    # Frontmatter.build: eingehende Werte in den Frontmatter-Hash mergen.
    # nil = „nicht anfassen"; alles andere setzt (leer/ungültig räumt ab —
    # den nil-Key entfernt das fm.compact des Aufrufers).
    def in_frontmatter!(fm, werte)
      FELDER.each do |feld|
        wert = werte[feld.name]
        fm[feld.key] = feld.bereinigt(wert) unless wert.nil?
      end
      fm
    end

    # Reader: DB-Spalten → Frontmatter (nur Gefülltes).
    def export!(fm, ki)
      FELDER.each { |feld| fm[feld.key] = ki[feld.name] if ki[feld.name].present? }
      fm
    end

    # Writer#update: Frontmatter → Attribute fürs DB-Update (alle Felder; ein
    # fehlender Key heißt dort „abgeräumt").
    def attribute_aus(fm) = FELDER.to_h { |feld| [feld.name, fm[feld.key]] }

    # KnowledgeIndexer: Datei → Datensatz, nur die rücklesbaren Felder.
    def indexieren!(item, fm)
      FELDER.select(&:index).each { |feld| item[feld.name] = feld.bereinigt(fm[feld.key]) }
    end

    # Controller, Anlege-Pfad: die typgebundenen Felder aus den Params.
    def anlage_felder(item_type, params)
      FELDER.select { |feld| feld.typ == item_type.to_s }
            .to_h { |feld| [feld.name, params[feld.name].presence] }.compact
    end
  end
end
