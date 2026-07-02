class SeedSynthesisKiTemplates < ActiveRecord::Migration[8.0]
  # #472 (Hans, 2026-06-02): Synthese-KI-Vorlagen als Ersatz fuer den
  # research_kind-gesteuerten SynthesisTemplate-Mechanismus (#471: Vorlagen
  # statt Subtypen/Research-Felder). Eine Vorlage je bisherigem Recherche-
  # Typ; item_type=synthesis, Body = Struktur-Geruest. Idempotent ueber den
  # Namen. Selbst-enthalten (keine App-Service-Abhaengigkeit).
  SECTIONS = {
    "Frage-Recherche"     => ["## Befund", "## Quellenlage", "## Offene Fragen"],
    "Thesen-Recherche"    => ["## These", "## Belege dafür", "## Belege dagegen", "## Bewertung"],
    "Quellen-Auswertung"  => ["## Zusammenfassung der Quelle", "## Einordnung", "## Bezug zur Fragestellung"],
    "Entitäts-Steckbrief" => ["## Wer / Was", "## Bedeutung", "## Verbindungen"],
    "Lücken-Recherche"    => ["## Kontext der Lücke", "## Befund", "## Einordnung"]
  }.freeze

  class MigrationKiTemplate < ActiveRecord::Base
    self.table_name = "ki_templates"
  end

  def up
    SECTIONS.each do |kind, sections|
      body = +"## Recherchefrage\n\n_(noch offen)_\n\n"
      sections.each { |h| body << "#{h}\n\n_(noch offen)_\n\n" }
      body << "## Anschluss an bestehendes Wissen\n\n" \
              "_(Verknüpfungen zu bestehenden Notizen — über Wikilinks.)_\n"
      rec = MigrationKiTemplate.find_or_initialize_by(name: "Synthese: #{kind}")
      rec.update!(item_type: "synthesis", title: "Synthese: ", body: body)
    end
  end

  def down
    MigrationKiTemplate.where("name LIKE ?", "Synthese: %").delete_all
  end
end
