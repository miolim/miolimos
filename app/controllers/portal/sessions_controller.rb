# #536 P1: Magic-Link-Flow (Variante 1, wie mit Hans geklärt).
#   GET  /portal/login         — E-Mail-Formular
#   POST /portal/login         — Link(s) mailen; Antwort IMMER gleich
#                                (kein E-Mail-Enumerieren)
#   GET  /portal/session/:token — Link konsumieren → Portal-Cookie
#   DELETE /portal/session     — Abmelden
module Portal
  class SessionsController < BaseController
    skip_before_action :require_portal_access

    def new
      redirect_to portal_root_path if current_access
    end

    # #619 Stufe 3: Sprache umschalten. Persistiert am Zugang (falls
    # eingeloggt) und im Cookie (greift auch auf der Login-Seite).
    def set_locale
      loc = params[:locale].to_s
      if PortalAccess::LOCALES.include?(loc)
        cookies[:portal_locale] = { value: loc, expires: 1.year.from_now, same_site: :lax }
        current_access&.update(locale: loc)
      end
      redirect_back fallback_location: portal_root_path
    end

    def create
      email = params[:email].to_s.strip.downcase
      if email.match?(URI::MailTo::EMAIL_REGEXP)
        PortalAccess.active.where(email: email).find_each do |access|
          PortalMailer.magic_link(access).deliver_later
        end
      end
      # Immer dieselbe Antwort — ob die Adresse einen Zugang hat, wird
      # nicht verraten.
      redirect_to portal_login_path, notice: t("portal.flash.link_sent")
    end

    def consume
      access = PortalAccess.from_magic_token(params[:token])
      if access
        sign_in_access(access)
        redirect_to portal_root_path
      else
        redirect_to portal_login_path, alert: t("portal.flash.link_invalid")
      end
    end

    def destroy
      sign_out_access
      redirect_to portal_login_path, notice: t("portal.flash.signed_out")
    end
  end
end
