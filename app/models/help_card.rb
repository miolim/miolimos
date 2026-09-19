# #1677 (aus immoOS #1658 übernommen; Hans dort): Hilfe zu einer Programm-Card — aufgerufen über das
# Fragezeichen im Card-Rücken.
#
# Zwei Bereiche mit unterschiedlichem Schreibrecht:
#   user_body    — was die Hausverwaltung sich selbst notiert (alle dürfen)
#   program_body — die Erklärung des Programms (nur Administratoren)
#
# Der Schlüssel ist die KARTEN-ART, nicht der einzelne Datensatz: Die Hilfe zur
# Grundstücks-Card gilt für jedes Grundstück. Optional mit Reiter dahinter,
# getrennt durch einen Punkt — „property.settlement". Der Punkt statt „#",
# damit der Schlüssel ohne Umkodierung in URL und Stack-Parameter passt.
class HelpCard < ApplicationRecord
  # Schlüssel-Zeichen bewusst eng: Karten-Arten und Reiternamen bestehen aus
  # Kleinbuchstaben, Ziffern, "_", ":" (list:persons) und dem Reiter-Punkt.
  KEY_RE = /\A[a-z0-9_:]+(\.[a-z0-9_]+)?\z/

  validates :key, presence: true, uniqueness: true, format: { with: KEY_RE }

  scope :mit_inhalt, -> {
    where("COALESCE(user_body, '') <> '' OR COALESCE(program_body, '') <> ''")
  }

  def self.fuer(key) = find_or_initialize_by(key: key.to_s)

  # Alle Schlüssel mit Inhalt — für die Anzeige des Fragezeichens im Rücken.
  # Eine Abfrage je Seitenaufbau, nicht eine je Card.
  def self.schluessel_mit_inhalt = mit_inhalt.pluck(:key).to_set

  # #1658 (Hans): „Vielleicht kann man das Icon noch etwas anders anzeigen, wenn
  # tatsächlich Text enthalten ist — damit man nicht ständig umsonst nach der
  # Hilfe schaut."
  def inhalt? = user_body.present? || program_body.present?

  # Die Karten-ART ohne Reiter. Gebraucht für das Fragezeichen im Rücken: Der
  # Server rendert es, ohne den offenen Reiter zu kennen, und zieht die
  # Schlüssel deshalb auf die Karte zusammen.
  def self.basis_schluessel(key) = key.to_s.split(".").first.to_s

  # ── Hilfe je Reiter (Stufe 2) ─────────────────────────────────────────
  # „property.settlement" ist die Hilfe zum Abrechnungs-Reiter der
  # Grundstücks-Card.
  #
  # #1658 R4 (Hans): „Wenn die Karte Reiter hat, gibt es zur Karte selbst keine
  # Hilfe, sondern nur zu den einzelnen Reitern." Deshalb gibt es auch keinen
  # Rückfall von einem Reiter auf die Karte — er hätte kein Ziel.
  def reiter = key.to_s.split(".")[1]

  def basis_schluessel = self.class.basis_schluessel(key)
end
