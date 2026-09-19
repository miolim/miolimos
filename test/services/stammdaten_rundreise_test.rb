require "test_helper"

# #1675 (R2): Ein neues Personen-/Organisations-Feld hieß bisher neun Stellen in
# sieben Dateien (Frontmatter-Build, Reader, Writer ×3, Indexer, EntityMerge,
# Formular, Controller) — dreimal in zwei Monaten gemacht (#1090, #1168, #1615).
# Wird eine vergessen, geht der Wert STILL verloren: Er fehlt im Export, und der
# nächste Indexer-Lauf oder Merge räumt ihn ab. Der Kontaktdaten-Verlust aus
# #1075 war diese Fehlerklasse.
#
# Dieser Test hält die Reise für JEDES Feld der Liste fest — und der Wächter am
# Ende zwingt bei jeder neuen Spalte zur Entscheidung: Stammdatum oder nicht.
class StammdatenRundreiseTest < ActiveSupport::TestCase
  PERSON = { first_name: "Erika", last_name: "Neumann", birth_name: "Altmann", gender: "female",
             salutation: "Liebe Erika", academic_title: "Dr.", orcid: "0000-0002-1825-0097" }.freeze
  ORGANISATION = { legal_form: LegalForms::OPTIONS.first }.freeze

  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
  end

  def werte(ki, felder) = felder.keys.index_with { |f| ki.reload[f] }

  test "Person: jedes Stammdatum uebersteht Export, Teil-Update und Indexer-Lauf" do
    with_isolated_miolimos_base do
      ki = FileProxy.create(actor: @hans, title: "Erika Neumann", item_type: :person, content: "")
      FileProxy.update(actor: @hans, knowledge_item: ki, **PERSON)
      assert_equal PERSON, werte(ki, PERSON), "nicht jedes Feld kam in der Datenbank an"

      fm = FileProxy::Reader.build_frontmatter_hash(ki.reload)
      PERSON.each { |feld, wert| assert_equal wert, fm[feld.to_s], "#{feld} fehlt im Export" }

      # Ein Update an etwas ganz anderem darf kein Stammdatum kosten.
      FileProxy.update(actor: @hans, knowledge_item: ki.reload, content: "Neuer Text")
      assert_equal PERSON, werte(ki, PERSON), "ein Teil-Update hat Stammdaten abgeräumt"

      # Der Indexer liest die Datei zurück — was im Export fehlte, wäre jetzt weg.
      KnowledgeIndexer.run
      assert_equal PERSON, werte(ki, PERSON), "der Indexer-Lauf hat Stammdaten abgeräumt"
    end
  end

  test "Organisation: die Rechtsform uebersteht dieselbe Reise" do
    with_isolated_miolimos_base do
      ki = FileProxy.create(actor: @hans, title: "Faro", item_type: :organization, content: "")
      FileProxy.update(actor: @hans, knowledge_item: ki, **ORGANISATION)
      assert_equal ORGANISATION, werte(ki, ORGANISATION)
      FileProxy.update(actor: @hans, knowledge_item: ki.reload, content: "x")
      KnowledgeIndexer.run
      assert_equal ORGANISATION, werte(ki, ORGANISATION)
    end
  end

  test "leerer String raeumt ein Feld ab, nil laesst es stehen" do
    with_isolated_miolimos_base do
      ki = FileProxy.create(actor: @hans, title: "Erika Neumann", item_type: :person, content: "")
      FileProxy.update(actor: @hans, knowledge_item: ki, **PERSON)
      FileProxy.update(actor: @hans, knowledge_item: ki.reload, birth_name: "", salutation: nil)
      assert_nil ki.reload.birth_name
      assert_equal "Liebe Erika", ki.salutation
    end
  end

  test "Katalogfelder nehmen nur Katalogwerte" do
    with_isolated_miolimos_base do
      ki = FileProxy.create(actor: @hans, title: "Erika Neumann", item_type: :person, content: "")
      FileProxy.update(actor: @hans, knowledge_item: ki, gender: "quatsch")
      assert_nil ki.reload.gender
    end
  end

  test "Zusammenfuehren fuellt jede Stammdaten-Luecke des Ziels" do
    with_isolated_miolimos_base do
      quelle = FileProxy.create(actor: @hans, title: "E. Neumann", item_type: :person, content: "")
      ziel   = FileProxy.create(actor: @hans, title: "Erika Neumann", item_type: :person, content: "")
      FileProxy.update(actor: @hans, knowledge_item: quelle, **PERSON)

      EntityMerge.merge!(source: quelle.reload, target: ziel.reload, actor: @hans)
      assert_equal PERSON, werte(ziel, PERSON), "der Merge hat ein Stammdatum der Quelle fallen lassen"
    end
  end
  # ── Wächter ─────────────────────────────────────────────────────────────

  test "jedes Feld der Liste hat oben einen Beispielwert — sonst reist es ungeprueft" do
    assert_equal KnowledgeItem::Stammdaten::NAMEN.sort, (PERSON.keys + ORGANISATION.keys).sort
  end

  # Spalten an knowledge_items, die bewusst KEIN skalares Stammdatum sind.
  KEIN_STAMMDATUM = {
    "Kern"            => %w[uuid title item_type body aliases tags search_vector render_mode],
    "Datei/Index"     => %w[file_path content_hash file_created_at file_updated_at indexed_at created_at updated_at deleted_at],
    "Herkunft"        => %w[creator_id provenance inbox_item_id bib_source_id locator_label locator_value published_at],
    "Gespräch"        => %w[parent_type parent_id_int parent_uuid],
    "Ablösung"        => %w[superseded_by_uuid superseded_at superseded_by_actor_id],
    "Verweise"        => %w[parent_org_uuid logo_uuid],        # über Titel/UUID aufgelöst, eigener Weg
    "Flags"           => %w[issuer vat_exempt personally_known] # eigene Semantik (OR beim Merge, Checkbox)
  }.freeze

  test "jede Spalte an knowledge_items ist ein Stammdatum oder bewusst keines" do
    bekannt   = KnowledgeItem::Stammdaten::NAMEN.map(&:to_s) + KEIN_STAMMDATUM.values.flatten
    unbekannt = KnowledgeItem.column_names - bekannt
    assert_empty unbekannt, <<~MSG
      Neue Spalte(n) an knowledge_items: #{unbekannt.join(', ')}

      Ist es ein Personen-/Organisations-Feld, das exportiert, zurückgelesen und
      beim Zusammenführen mitgenommen werden soll? Dann EINE Zeile in
      app/models/knowledge_item/stammdaten.rb (und oben ein Beispielwert) — den
      Rest erledigt die Liste. Wenn nicht: hier unter KEIN_STAMMDATUM eintragen.
    MSG
    verwaist = bekannt - KnowledgeItem.column_names
    assert_empty verwaist, "verweist auf Spalten, die es nicht mehr gibt: #{verwaist.join(', ')}"
  end

  test "ein unbekanntes Feld wird abgewiesen statt verschluckt" do
    with_isolated_miolimos_base do
      ki = FileProxy.create(actor: @hans, title: "Erika Neumann", item_type: :person, content: "")
      assert_raises(ArgumentError) { FileProxy.update(actor: @hans, knowledge_item: ki, geburtsname: "Tippfehler") }
    end
  end
end
