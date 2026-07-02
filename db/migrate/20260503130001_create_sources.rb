class CreateSources < ActiveRecord::Migration[8.1]
  def change
    create_table :sources do |t|
      # Citation-Key (Pandoc-Cite-Syntax: `[@slug]`). Lowercase mit
      # Hyphen, eindeutig im System.
      t.string :slug, null: false

      # CSL-Type-Enum: book, chapter, article-journal, legal_case,
      # legislation, webpage, dataset, software, report, thesis,
      # manuscript, patent, motion_picture, song, post, post-weblog,
      # broadcast, interview, … Speichern als String, weil das CSL-Schema
      # versioniert ist und neue Typen ohne Migration unterstützt werden
      # sollen. Validation in Source-Model gegen aktuelle Liste.
      t.string :csl_type, null: false

      t.string :title, null: false
      t.string :container_title    # Journal/Sammelband-Titel
      t.string :publisher
      t.string :publisher_place

      # Datum mit Granularitäts-Flexibilität: parsed Date für Sortierung
      # + originaler String für Anzeige (z.B. "2023" oder "2023-04").
      t.date    :issued_date
      t.string  :issued_string
      t.date    :accessed

      t.string :edition
      t.string :volume
      t.string :issue
      t.string :pages              # "33–47" oder "S. 12"
      t.text   :abstract
      t.string :language
      t.string :archive
      t.string :archive_location
      t.string :url

      # Hierarchie: Buchteil → Buch, Aufsatz → Sammelband.
      t.references :parent_source, foreign_key: { to_table: :sources }, type: :bigint

      # Juristische Felder — nur für legal_case / legislation gefüllt.
      t.string :jurisdiction
      t.string :court
      t.string :docket_number
      t.jsonb  :parallel_citations, default: []  # [{reporter, volume, page}]

      t.references :creator, null: false, foreign_key: { to_table: :actors }
      t.timestamps
    end

    add_index :sources, :slug, unique: true
    add_index :sources, :csl_type
    add_index :sources, :issued_date
    add_index :sources, "lower(title)"
  end
end
