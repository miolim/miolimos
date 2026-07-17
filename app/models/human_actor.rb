class HumanActor < Actor
  has_secure_password validations: false

  # #1051: TOTP-Secret verschlüsselt at rest (Lockbox, wie OauthCredential).
  has_encrypted :otp_secret

  validates :email,    presence: true, uniqueness: true
  validates :password, length: { minimum: 8 }, if: -> { password.present? }

  # #1051: TOTP-Zweitfaktor (Opt-in pro Nutzer, Settings → Sicherheit).
  # Enrollment: Settings::TwoFactorController hält das Kandidaten-Secret in
  # der Session, bis der Nutzer einen gültigen Code bestätigt — erst
  # enable_otp! schreibt es an den Actor.
  OTP_ISSUER = "miolimOS".freeze
  OTP_RECOVERY_CODE_COUNT = 8

  def otp_enabled? = otp_enabled_at.present?

  def otp_provisioning_uri(secret = otp_secret)
    ROTP::TOTP.new(secret, issuer: OTP_ISSUER).provisioning_uri(email)
  end

  # Verifiziert einen TOTP-Code gegen das gespeicherte Secret. drift_behind
  # toleriert eine gerade abgelaufene Code-Periode (Tipp-Latenz); `after:`
  # verbrennt den benutzten Timestep, damit derselbe Code nicht zweimal
  # durchgeht (Replay im 30s-Fenster).
  def verify_otp_code!(code)
    return false unless otp_enabled? && otp_secret.present?
    ts = ROTP::TOTP.new(otp_secret, issuer: OTP_ISSUER)
           .verify(code.to_s.gsub(/\s/, ""), drift_behind: 30, after: otp_consumed_timestep)
    return false unless ts
    update!(otp_consumed_timestep: ts)
    true
  end

  # Recovery-Code prüfen und bei Treffer verbrauchen (Einmal-Codes).
  # Gespeichert sind nur SHA256-Digests.
  def verify_otp_recovery_code!(code)
    digest = self.class.otp_recovery_digest(code)
    return false unless otp_recovery_codes.include?(digest)
    update!(otp_recovery_codes: otp_recovery_codes - [digest])
    true
  end

  # Aktiviert 2FA mit dem bestätigten Secret und erzeugt frische
  # Recovery-Codes. Gibt die Klartext-Codes zurück — die einzige Stelle,
  # an der sie je sichtbar sind.
  def enable_otp!(secret)
    codes = nil
    transaction do
      self.otp_secret = secret
      self.otp_enabled_at = Time.current
      self.otp_consumed_timestep = nil
      codes = reset_otp_recovery_codes
      save!
    end
    codes
  end

  def regenerate_otp_recovery_codes!
    codes = reset_otp_recovery_codes
    save!
    codes
  end

  def disable_otp!
    update!(otp_secret: nil, otp_enabled_at: nil,
            otp_recovery_codes: [], otp_consumed_timestep: nil)
  end

  def self.otp_recovery_digest(code)
    Digest::SHA256.hexdigest(code.to_s.strip.downcase)
  end

  private

  def reset_otp_recovery_codes
    codes = Array.new(OTP_RECOVERY_CODE_COUNT) do
      SecureRandom.alphanumeric(10).downcase.scan(/.{5}/).join("-")
    end
    self.otp_recovery_codes = codes.map { |c| self.class.otp_recovery_digest(c) }
    codes
  end
end
