# #1499 (Hans): "Wie lange gelten die Token und lassen sie sich einzeln
# zurueckziehen?"
#
# Vorher: ein Token je Agent, unbegrenzt gueltig, in einer Spalte am Actor.
# Rotieren traf alles gleichzeitig, wo dieser Agent lief — und ob ein Token
# ueberhaupt noch benutzt wurde, wusste niemand.
#
# Ein Token ist jetzt ein eigener Gegenstand: mit Namen (wofuer ist es?),
# Ablauf, letzter Benutzung und eigenem Rueckzug. Der Klartext existiert
# ausschliesslich im Augenblick des Erzeugens; gespeichert wird nur sein
# Pruefwert — wie bei den Zugriffstoken von GitHub.
class ApiToken < ApplicationRecord
  belongs_to :actor

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true

  # Der Klartext ist FLUECHTIG: `token` liefert ihn nur in derselben
  # Objekt-Instanz, in der er erzeugt wurde. Nach einem Reload gibt es ihn
  # nirgends mehr — auch nicht fuer mich.
  attr_reader :token

  scope :aktiv, -> {
    where(revoked_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current)
  }
  scope :ordered, -> { order(Arel.sql("revoked_at IS NOT NULL"), created_at: :desc) }

  # 32 Byte Zufall, hex — nicht zu raten und ohne Sonderzeichen, damit es
  # sich in Konfigurationsdateien und Kopfzeilen einfach handhaben laesst.
  def self.generate_secret = SecureRandom.hex(32)

  # Legt ein Token an und gibt es MIT Klartext zurueck. Der Aufrufer hat
  # genau diese eine Gelegenheit, ihn anzuzeigen.
  def self.issue!(actor:, name:, expires_at: nil)
    secret = generate_secret
    t = create!(actor: actor, name: name, expires_at: expires_at,
                token_digest: Actor.digest_api_token(secret))
    t.instance_variable_set(:@token, secret)
    t
  end

  # Der eine Weg vom Klartext zum gueltigen Token. Bewusst hier und nicht im
  # Controller: Wer die Regeln fuer "gueltig" sucht, soll sie an einer Stelle
  # finden — nicht verteilt auf Abfragen.
  def self.authenticate(secret)
    return nil if secret.blank?
    aktiv.find_by(token_digest: Actor.digest_api_token(secret))
  end

  def revoked?  = revoked_at.present?
  def expired?  = expires_at.present? && expires_at <= Time.current
  def usable?   = !revoked? && !expired?

  def revoke!
    update!(revoked_at: Time.current) unless revoked?
  end

  # #1499 Punkt 2: Benutzung mitschreiben. `update_column` bewusst — das ist
  # eine Randnotiz zu jedem API-Aufruf und darf weder Rueckrufe ausloesen noch
  # `updated_at` bewegen; sonst sieht jedes Token bei jedem Aufruf aus wie
  # gerade geaendert.
  def benutzt!
    update_column(:last_used_at, Time.current)
  end

  # "Seit 40 Tagen nicht benutzt" ist die Frage, die man beim Aufraeumen
  # stellt. Nie benutzt = nil, nicht 0 — das ist ein Unterschied.
  def tage_ungenutzt
    return nil if last_used_at.blank?
    ((Time.current - last_used_at) / 1.day).floor
  end
end
