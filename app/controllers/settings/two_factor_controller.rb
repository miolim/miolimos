# #1051: TOTP-Selbstverwaltung — arbeitet IMMER auf real_actor (dem
# tatsächlich eingeloggten Nutzer), nie auf dem Preview-Actor; mutierende
# Requests sind während einer Vorschau ohnehin geblockt. Das Kandidaten-
# Secret lebt bis zur Code-Bestätigung nur in der Session — erst ein
# gültiger Code schreibt es an den Actor (kein „halb eingerichtetes" 2FA).
class Settings::TwoFactorController < Settings::BaseController
  SECURITY_STACK = "list:settings,settings:security".freeze

  def start
    session[:otp_setup_secret] = ROTP::Base32.random
    redirect_to settings_path(stack: SECURITY_STACK)
  end

  def confirm
    secret = session[:otp_setup_secret]
    return redirect_to settings_path(stack: SECURITY_STACK), alert: t("settings.two_factor.no_pending_setup") unless secret

    code = params[:code].to_s.gsub(/\s/, "")
    if ROTP::TOTP.new(secret, issuer: HumanActor::OTP_ISSUER).verify(code, drift_behind: 30)
      codes = real_actor.enable_otp!(secret)
      session.delete(:otp_setup_secret)
      # Einmalige Anzeige der Recovery-Codes über den Flash (nur Digests
      # liegen in der DB). Acht kurze Codes — passt problemlos in den
      # Cookie-Store.
      flash[:otp_recovery_codes] = codes
      redirect_to settings_path(stack: SECURITY_STACK), notice: t("settings.two_factor.enabled")
    else
      redirect_to settings_path(stack: SECURITY_STACK), alert: t("settings.two_factor.wrong_code")
    end
  end

  def regenerate_codes
    return redirect_to settings_path(stack: SECURITY_STACK) unless real_actor.otp_enabled?
    flash[:otp_recovery_codes] = real_actor.regenerate_otp_recovery_codes!
    redirect_to settings_path(stack: SECURITY_STACK), notice: t("settings.two_factor.codes_regenerated")
  end

  # Deaktiviert 2FA bzw. bricht ein laufendes Enrollment ab (disable_otp!
  # ist idempotent, das Session-Secret fliegt in beiden Fällen raus).
  def disable
    real_actor.disable_otp!
    session.delete(:otp_setup_secret)
    redirect_to settings_path(stack: SECURITY_STACK), notice: t("settings.two_factor.disabled")
  end
end
