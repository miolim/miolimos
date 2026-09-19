class ApplicationController < ActionController::Base
  include Gated
  # #1582 (aus immoOS #1581): ohne 2FA beim Start zuerst die Sicherheits-Card.
  include SicherheitZuerst

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

  # #1675: DIE Stelle, an der ein Controller ein Eltern- oder Zielobjekt aus
  # der URL holt (`/tasks/:task_id/replies`, `predecessor_id=…`). Vorher stand
  # in rund einem Dutzend verschachtelter Controller je ein eigenes
  # `Task.find(params[:task_id])` — und keines kannte die Sichtbarkeit aus
  # #602. Ein Mitglied konnte fremde Antworten lesen, fremde Aufgaben
  # kommentieren und sie in ein eigenes Thema ziehen.
  #
  #   nicht sichtbar              → 404 (wie die Hauptseiten; verrät nicht,
  #                                 dass es das Objekt gibt)
  #   sichtbar, aber nur lesbar   → bei schreibenden Requests 403
  #
  # `write:` sagt, ob der Aufruf das Objekt VERÄNDERT. Vorgabe: jedes Verb
  # außer GET/HEAD. Ausnahmen nennt der Aufrufer ausdrücklich — `write: false`
  # für ein POST mit Lese-Semantik oder für ein bloßes VerknüpfungsZIEL (wer
  # etwas Eigenes mit einer fremden, lesbaren Aufgabe verknüpft, ändert die
  # fremde nicht).
  def find_visible!(scope, value, by: nil, write: nil)
    klass = scope.respond_to?(:klass) ? scope.klass : scope
    ensure_visible!(scope.find_by((by || klass.primary_key) => value), klass, write: write)
  end

  # Der Kern von find_visible! für ein schon geladenes Objekt (z.B. ein Thema,
  # das per Slug ODER id gesucht wurde). nil zählt als „nicht sichtbar".
  def ensure_visible!(record, klass = record.class, write: nil)
    unless record&.visible_to?(current_actor)
      raise ActiveRecord::RecordNotFound.new("Couldn't find #{klass.name}", klass.name)
    end
    write = !(request.get? || request.head?) if write.nil?
    if write && !record.writable_by?(current_actor)
      raise AccessGate::Unauthorized,
            "#{current_actor&.name} darf #{klass.name} nicht ändern (nur Betrachter)"
    end
    record
  end

  # Ein auf anderem Weg gefundenes VerknüpfungsZIEL (Resolver, Slug-Suche)
  # nur durchlassen, wenn der Nutzer es sehen darf — sonst nil.
  def only_visible(record)
    record if record&.visible_to?(current_actor)
  end

  # Themen kommen aus Pickern mal als Slug, mal als id.
  def find_visible_topic!(raw, write: false)
    ensure_visible!(Topic.find_by(slug: raw) || Topic.find_by(id: raw), Topic, write: write)
  end

  # Wie find_visible!, aber nil statt 404 — für optionale Ziele.
  def find_visible(scope, value, **opts)
    return nil if value.blank?
    find_visible!(scope, value, **opts)
  rescue ActiveRecord::RecordNotFound
    nil
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
