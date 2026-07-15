# #995 (Hans): Internetmarke-Zugangsdaten des aktuellen Nutzers verwalten
# (Portokassen-Login + DHL-API-App). Secrets landen verschlüsselt in
# InternetmarkeCredential; „Verbindung testen" macht einen Login ohne Kauf
# und zeigt den Portokassen-Stand.
class Settings::InternetmarkeController < Settings::BaseController
  def show
    redirect_to settings_path(stack: "list:settings,settings:internetmarke")
  end

  def update
    cred = current_actor.internetmarke_credential ||
           current_actor.build_internetmarke_credential
    attrs = params.permit(:portokasse_email, :client_id).to_h
    # Leere Secret-Felder = vorhandenen Wert behalten (Formular zeigt sie nie an).
    %i[portokasse_password client_secret].each do |key|
      attrs[key] = params[key] if params[key].present?
    end
    cred.assign_attributes(attrs)
    if cred.save
      redirect_to settings_internetmarke_path, notice: t("settings.internetmarke.saved")
    else
      redirect_to settings_internetmarke_path,
                  alert: cred.errors.full_messages.to_sentence
    end
  end

  def destroy
    current_actor.internetmarke_credential&.destroy!
    redirect_to settings_internetmarke_path, notice: t("settings.internetmarke.removed")
  end

  # Login gegen die API (ohne Kauf) — verifiziert Zugangsdaten + zeigt Wallet.
  def test
    cred = current_actor.internetmarke_credential
    unless cred
      redirect_to settings_internetmarke_path,
                  alert: t("settings.internetmarke.none_yet") and return
    end
    client = Internetmarke::Client.new(cred)
    client.authenticate
    balance = client.wallet_balance
    msg = if balance
      t("settings.internetmarke.test_ok_balance",
        balance: format("%.2f €", balance.to_i / 100.0).tr(".", ","))
    else
      t("settings.internetmarke.test_ok")
    end
    redirect_to settings_internetmarke_path, notice: msg
  rescue Internetmarke::Client::Error => e
    redirect_to settings_internetmarke_path,
                alert: t("settings.internetmarke.test_failed", error: e.message)
  end

  private

  def controller_resource_type = "Actor"

  def controller_action_to_capability
    %w[update destroy test].include?(action_name) ? "update" : "read"
  end
end
