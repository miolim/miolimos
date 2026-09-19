require "test_helper"

# #1675: Wächter über die handgepflegte Verweisliste von EntityMerge.
#
# EntityMerge#repoint_references zählt jede Spalte einzeln auf, die per UUID
# auf ein Person-/Org-KI zeigen kann. Kommt eine neue Verweis-Spalte dazu und
# niemand denkt an den Merge, bleibt der Verweis still an der Quelle hängen —
# und zeigt nach dem Zusammenführen auf den Papierkorb. Genau das ist mit dem
# Portalzugang und der Bankumsatz-Gegenpartei passiert (#1631) und fiel erst
# durch eine Spaltenprüfung von Hand auf.
#
# Dieser Test IST diese Spaltenprüfung: Jede Spalte im Schema, die nach einem
# KI-Verweis aussieht, muss entweder vom Merge umgehängt werden oder hier mit
# Begründung als Ausnahme stehen. Schlägt er fehl, ist die Antwort fast immer
# eine neue `repoint`-Zeile in EntityMerge (plus ein Verhaltenstest), selten
# ein neuer Eintrag unten.
class EntityMergeSpaltenwaechterTest < ActiveSupport::TestCase
  VERWEIS_SPALTE = /(_uuid|knowledge_item_id)\z/

  # Spalten, die ein eigener move_*-Weg mit Dubletten-Abgleich umzieht.
  EIGENER_WEG = {
    "contact_points.knowledge_item_uuid"   => :move_contact_points,
    "postal_addresses.knowledge_item_uuid" => :move_postal_addresses,
    "bank_accounts.knowledge_item_uuid"    => :move_bank_accounts,
    "identifiers.knowledge_item_uuid"      => :move_identifiers
  }.freeze

  # Bewusst NICHT umgehängt — mit Grund.
  AUSNAHMEN = {
    "knowledge_item_references.source_uuid" =>
      "ausgehende Verweise der Quelle werden gelöscht; der Reindex des Ziels baut sie aus dem angehängten Body neu",
    "knowledge_items.logo_uuid" =>
      "zeigt auf ein Bild-KI, nie auf Person/Org; das Logo der Quelle wandert über export_target! (#1168)",
    "wikilink_research_jobs.source_knowledge_item_id" =>
      "Auftragsprotokoll einer abgeschlossenen Recherche, kein lebender Verweis",
    "wikilink_research_jobs.target_knowledge_item_id" =>
      "Auftragsprotokoll einer abgeschlossenen Recherche, kein lebender Verweis"
  }.freeze

  # Zeichnet auf, welche Spalten repoint_references anfasst, ohne etwas zu tun.
  class Mitschreiber < EntityMerge
    attr_reader :gesehen

    def initialize(*)
      super
      @gesehen = []
    end

    private

    def repoint(scope, column, **)
      model = scope.respond_to?(:klass) ? scope.klass : scope
      @gesehen << "#{model.table_name}.#{column}"
    end
  end

  def umgehaengte_spalten
    quelle = KnowledgeItem.new(uuid: SecureRandom.uuid, item_type: :person)
    ziel   = KnowledgeItem.new(uuid: SecureRandom.uuid, item_type: :person)
    m = Mitschreiber.new(quelle, ziel, nil)
    m.send(:repoint_references)
    m.gesehen
  end

  def verweis_spalten_im_schema
    conn = ActiveRecord::Base.connection
    (conn.tables - %w[schema_migrations ar_internal_metadata]).flat_map do |tabelle|
      conn.columns(tabelle).map(&:name).grep(VERWEIS_SPALTE).map { |spalte| "#{tabelle}.#{spalte}" }
    end
  end

  test "jede KI-Verweis-Spalte wird umgehaengt oder ist begruendet ausgenommen" do
    bekannt = umgehaengte_spalten + EIGENER_WEG.keys + AUSNAHMEN.keys
    vergessen = verweis_spalten_im_schema - bekannt

    assert_empty vergessen, <<~MSG
      Diese Spalten sehen nach einem Verweis auf ein KI aus, aber EntityMerge
      hängt sie nicht um — nach dem Zusammenführen zweier Personen zeigten sie
      auf die Quelle im Papierkorb:

        #{vergessen.join("\n  ")}

      Entweder eine `repoint`-Zeile in EntityMerge#repoint_references ergänzen
      (und einen Verhaltenstest in entity_merge_test.rb), oder — wenn die Spalte
      nie auf Person/Org zeigen kann — hier unter AUSNAHMEN begründen.
    MSG
  end

  test "die Listen hier zeigen auf Spalten und Wege, die es noch gibt" do
    schema = verweis_spalten_im_schema
    verwaist = (EIGENER_WEG.keys + AUSNAHMEN.keys + umgehaengte_spalten) - schema
    assert_empty verwaist, "Verweist auf Spalten, die es nicht mehr gibt: #{verwaist.join(', ')}"

    EIGENER_WEG.each_value do |weg|
      assert EntityMerge.private_method_defined?(weg), "EntityMerge##{weg} fehlt"
    end
  end
end
