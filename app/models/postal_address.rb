# #532 (Hans, 2026-06-08): strukturierte Postadresse eines Person/Org-KI.
# EN16931: line1/line2 (Adresszeilen), postal_code, city, country. DB ist
# Source of Truth — DB-direkt editiert, keine Frontmatter-Sync.
class PostalAddress < ApplicationRecord
  belongs_to :knowledge_item, class_name: "KnowledgeItem",
             foreign_key: :knowledge_item_uuid, primary_key: :uuid

  # #622: Adresstyp — liegenschaft (Besuchsanschrift, Default) oder
  # post (Versandanschrift, oft Postfach). Briefe/DIN-Fenster nehmen
  # bevorzugt die Postadresse (KnowledgeItem#mailing_address).
  enum :kind, { liegenschaft: 0, post: 1 }, default: :liegenschaft

  # #1073: Gueltigkeitszeitraum. Beide Grenzen optional — leer heisst offen,
  # zwei leere Grenzen heissen unbefristet (der Normalfall und der Zustand
  # aller Bestandsadressen).
  validate :valid_until_not_before_valid_from

  scope :ordered, -> { order(:position, :id) }
  scope :billing, -> { where(billing: true) }

  # Am Stichtag gueltig: Beginn nicht in der Zukunft, Ende nicht in der
  # Vergangenheit. NULL zaehlt jeweils als „offen".
  scope :current, ->(on = Date.current) {
    where("valid_from IS NULL OR valid_from <= ?", on)
      .where("valid_until IS NULL OR valid_until >= ?", on)
  }
  # Abgelaufen oder noch nicht angefangen — alles, was `current` nicht traegt.
  scope :former, ->(on = Date.current) {
    where("valid_until IS NOT NULL AND valid_until < ?", on)
  }

  def current?(on = Date.current)
    (valid_from.nil?  || valid_from  <= on) &&
      (valid_until.nil? || valid_until >= on)
  end

  def former?(on = Date.current) = valid_until.present? && valid_until < on
  def future?(on = Date.current) = valid_from.present?  && valid_from  > on

  # Kurzform fuer die Anzeige: „seit 01.06.2026", „bis 31.05.2026",
  # „01.01.2020 – 31.05.2026" oder nil, wenn unbefristet.
  def validity_label
    return nil if valid_from.blank? && valid_until.blank?
    from = valid_from&.strftime("%d.%m.%Y")
    till = valid_until&.strftime("%d.%m.%Y")
    return "seit #{from}" if till.blank?
    return "bis #{till}"  if from.blank?
    "#{from} – #{till}"
  end

  # Adresszeilen fürs DIN-Adressfeld: Straße, (Zusatz), "PLZ Ort", (Land).
  def lines
    [line1, line2, [postal_code, city].compact_blank.join(" ").presence, country]
      .compact_blank
  end

  def oneline = lines.join(" · ")
  def blank?  = lines.empty?

  private

  def valid_until_not_before_valid_from
    return if valid_from.blank? || valid_until.blank?
    return if valid_until >= valid_from
    errors.add(:valid_until, "darf nicht vor dem Beginn liegen")
  end
end
