# #536 P1: Basis aller Portal-Controller. Erbt BEWUSST direkt von
# ActionController::Base — kein Gated, keine interne Session, kein
# current_actor. Das Portal ist eine eigene, nach außen gerichtete
# Mini-App mit eigener Auth (Magic-Link → Portal-Cookie) und einer
# harten Isolations-Regel:
#
#   JEDE Daten-Query läuft über current_access.topic — niemals über
#   freie Parameter. Default-deny: ohne gültige Portal-Session gibt es
#   nur die Login-Seite.
module Portal
  class BaseController < ActionController::Base
    layout "portal"

    COOKIE_NAME = :portal_session

    before_action :require_portal_access

    # #619 Stufe 3: Portal in DE/EN. Quelle der Wahrheit ist der Zugang
    # (locale je PortalAccess); für die Login-Seite (noch kein Zugang)
    # dient ein Cookie als Fallback. Default = I18n.default_locale.
    around_action :switch_portal_locale

    helper_method :current_access, :current_project, :portal_locale

    private

    def switch_portal_locale(&block)
      I18n.with_locale(portal_locale, &block)
    end

    def portal_locale
      loc = current_access&.locale.presence || cookies[:portal_locale]
      PortalAccess::LOCALES.include?(loc) ? loc : I18n.default_locale
    end

    def current_access
      @current_access ||= PortalAccess.from_session_token(cookies.signed[COOKIE_NAME])
    end

    def current_project
      current_access&.topic
    end

    def require_portal_access
      return if current_access
      redirect_to portal_login_path
    end

    def sign_in_access(access)
      cookies.signed[COOKIE_NAME] = {
        value: access.session_token,
        expires: PortalAccess::SESSION_TTL.from_now,
        httponly: true, same_site: :lax,
        secure: Rails.env.production?
      }
      access.update!(last_login_at: Time.current)
    end

    def sign_out_access
      cookies.delete(COOKIE_NAME)
    end

    # ── Inhalts-Queries: EINE Quelle (Portal::Content), geteilt mit dem
    # Export — Übergabe-Artefakt ≡ eingeloggte Sicht. ──
    def project_milestones = Portal::Content.milestones(current_project)
    def shared_artifacts   = Portal::Content.shared_artifacts(current_project)
    def portal_messages    = Portal::Content.messages(current_project)
  end
end
