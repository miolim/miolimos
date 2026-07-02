class CreateSourceIdentifiers < ActiveRecord::Migration[8.1]
  def change
    create_table :source_identifiers do |t|
      t.references :source, null: false, foreign_key: true
      # scheme: DOI | ISBN | ECLI | ORCID | ROR | URN | PMID | arXiv |
      #         juris-id | ELI | ISSN | …
      t.string :scheme, null: false
      t.string :value,  null: false
      t.timestamps
    end
    add_index :source_identifiers, [:scheme, :value]
    add_index :source_identifiers, [:source_id, :scheme, :value], unique: true,
              name: "idx_source_identifiers_uniq"
  end
end
