# #1051: TOTP-Zweitfaktor für HumanActors. Secret verschlüsselt via
# Lockbox (Ciphertext-Spalte), Recovery-Codes als SHA256-Digests im
# jsonb-Array, otp_consumed_timestep verhindert Code-Replay innerhalb
# des 30s-Fensters. otp_enabled_at nil = 2FA aus (Opt-in pro Nutzer).
class AddOtpToActors < ActiveRecord::Migration[8.1]
  def change
    change_table :actors, bulk: true do |t|
      t.text     :otp_secret_ciphertext
      t.datetime :otp_enabled_at
      t.jsonb    :otp_recovery_codes, null: false, default: []
      t.bigint   :otp_consumed_timestep
    end
  end
end
