# #428 (Hans, 2026-05-31): Zentrale Tag-Entitaet — gemeinsames Vokabular
# ueber alle Entitaeten (Tasks + KnowledgeItems) plus Metadaten
# (Farbe/Beschreibung). Die eigentliche Zuordnung lebt derzeit noch in den
# tags-Array-Spalten; `taggings` spiegelt sie (Fundament fuer Umbenennen/
# Mergen). Tag-Namen sind normalisiert (downcase + strip), case-insensitiv
# eindeutig.
class Tag < ApplicationRecord
  has_many :taggings, dependent: :destroy

  normalizes :name, with: ->(v) { v.to_s.strip.downcase }

  validates :name, presence: true,
    uniqueness: { case_sensitive: false }

  scope :alphabetical, -> { order(Arel.sql("lower(name)")) }

  # Vokabular = alle bekannten Tag-Namen (fuer Autocomplete-Vorschlaege,
  # entitaets-uebergreifend). Optionaler Substring-Filter.
  def self.vocabulary(q = nil)
    rel = alphabetical
    rel = rel.where("lower(name) LIKE ?", "%#{q.to_s.strip.downcase}%") if q.present?
    rel.pluck(:name)
  end

  # Tag per Name holen/anlegen (normalisiert).
  def self.ensure(name)
    n = name.to_s.strip.downcase
    return nil if n.empty?
    find_or_create_by(name: n)
  end
end
