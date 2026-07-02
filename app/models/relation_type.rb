class RelationType < ApplicationRecord
  # #239 Phase D: kuratiertes Vokabular fuer Beziehungs-Labels.
  # `name` ist case-insensitive eindeutig. `inverse_name` zeigt die
  # Beziehung aus Sicht des Targets („loest aus" ↔ „wird ausgeloest von").
  # #155 Phase 5a: `ebene` ist Hans' Achse (inhaltlich/organisatorisch/
  # sozial/politisch) — pro Typ optional gepflegt, fuer Backlinks-Gruppierung.
  EBENEN = %w[inhaltlich organisatorisch sozial politisch].freeze

  validates :name, presence: true, length: { maximum: 80 }
  validates :name, uniqueness: { case_sensitive: false }
  validates :inverse_name, length: { maximum: 80 }
  validates :ebene, inclusion: { in: EBENEN, allow_nil: true, allow_blank: true }

  before_validation :normalize_name
  before_validation :normalize_ebene

  def self.find_by_label(label)
    return nil if label.blank?
    where("LOWER(name) = ?", label.to_s.downcase.strip).first
  end

  # Aggregation: wie viele Relations tragen ein Label, das diesem Typ
  # entspricht? Wird in der Einstellungs-Liste gezeigt.
  def usage_count
    Relation.active.where("LOWER(label) = ?", name.downcase).count
  end

  private

  def normalize_name
    self.name = name.to_s.strip if name.present?
    self.inverse_name = inverse_name.to_s.strip.presence
  end

  def normalize_ebene
    self.ebene = ebene.to_s.strip.downcase.presence
  end
end
