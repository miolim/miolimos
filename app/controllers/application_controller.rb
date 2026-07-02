class ApplicationController < ActionController::Base
  include Gated

  # require_login must run BEFORE Gated's enforce_access_gate, otherwise
  # AccessGate receives a nil current_actor (same bug we fixed in Api::V1).
  prepend_before_action :require_login
  before_action :set_current_actor
  helper_method :current_actor

  rescue_from AccessGate::Unauthorized, with: :render_forbidden

  allow_browser versions: :modern

  helper_method :real_actor, :previewing?

  # #602 S3: „Als X ansehen" — Read-only-Vorschau. Solange
  # session[:preview_actor_id] gesetzt ist (nur durch einen Admin,
  # PreviewSessionsController), läuft die GESAMTE Sichtbarkeits- und
  # Capability-Auswertung über den Vorschau-Nutzer: der Admin sieht
  # exakt, was X sieht — inklusive 404s und fehlender Knöpfe. Alle
  # mutierenden Requests sind währenddessen geblockt (block_writes_
  # during_preview), die Vorschau ist also nebenwirkungsfrei.
  before_action :block_writes_during_preview

  # #619 (Hans, 2026-06-18): UI-Sprache pro Nutzer. Der eingeloggte
  # Actor traegt seine Locale in den preferences (pref_locale); ohne
  # Wahl greift die App-Default-Locale (:de). around_action, damit
  # I18n.locale nach dem Request wieder zurueckgesetzt wird (Thread-
  # Wiederverwendung bei Puma).
  around_action :switch_locale

  private

  def switch_locale(&action)
    locale = current_actor&.pref_locale || I18n.default_locale
    I18n.with_locale(locale, &action)
  end

  def current_actor
    return @current_actor if defined?(@current_actor)
    @current_actor =
      if real_actor&.admin? && session[:preview_actor_id]
        HumanActor.active.find_by(id: session[:preview_actor_id]) || real_actor
      else
        real_actor
      end
  end

  # Der tatsächlich eingeloggte Nutzer (für Banner + Vorschau-Ende).
  def real_actor
    return @real_actor if defined?(@real_actor)
    @real_actor = session[:actor_id] ? HumanActor.find_by(id: session[:actor_id]) : nil
  end

  def previewing?
    current_actor && real_actor && current_actor.id != real_actor.id
  end

  def block_writes_during_preview
    return unless previewing?
    return if request.get? || request.head?
    # Vorschau beenden + Logout müssen immer funktionieren.
    return if %w[preview_sessions sessions].include?(controller_path)
    message = "Vorschau-Modus: nur lesen. Vorschau beenden, um zu arbeiten."
    respond_to do |format|
      format.html { redirect_back fallback_location: dashboard_path, alert: message }
      format.any  { render plain: message, status: :forbidden }
    end
  end

  def require_login
    return if current_actor
    session[:return_to] = request.fullpath if request.get?
    redirect_to login_path, alert: t("sessions.login_required")
  end

  def set_current_actor
    Current.actor = current_actor
  end

  def render_forbidden(exception)
    respond_to do |format|
      format.html { render "shared/forbidden", status: :forbidden, locals: { message: exception.message }, layout: "auth" }
      format.json { render json: { error: exception.message }, status: :forbidden }
      format.any  { head :forbidden }
    end
  end

  # #160 Phase 5: Server-seitiges Edit-Tracking. Wird von Edit-Actions
  # (z.B. toggle_done, update) aufgerufen, damit auch Interaktionen
  # außerhalb der Detail-Seite (z.B. Dashboard-Klicks) im Verlauf
  # auftauchen. Idempotent (upsert mit 60-s-Fenster) — wenn die Detail-
  # Seite mit dem JS-View-Tracker schon eine View geschrieben hat,
  # ergänzt diese Aufnahme nur was_edited=true.
  def record_edit_view(viewable)
    return unless viewable && current_actor
    type = viewable.class.name
    return unless ActorView::TRACKABLE_TYPES.include?(type)
    ActorView.upsert_for!(
      actor:         current_actor,
      viewable_type: type,
      viewable_id:   viewable.id,
      duration_ms:   0,
      was_edited:    true
    )
  rescue StandardError => e
    Rails.logger.warn("record_edit_view failed: #{e.message}")
  end
end
