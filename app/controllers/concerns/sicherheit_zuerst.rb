# #1582 (Hans, aus immoOS #1581 übernommen): „Auch bei miolim_os sollte man
# beständig auf 2FA hingewiesen werden, wenn es noch nicht eingerichtet ist."
# immoOS #1581: „Wenn keine 2FA eingerichtet ist, soll bei Start immer zuerst
# die Sicherheit-Card angezeigt werden."
#
# Eigenes Concern, weil zwei Controller es brauchen, die nicht voneinander
# erben: der SessionsController (Login — er darf gerade NICHT hinter
# `require_login` stehen) und der StartController (Start ohne neuen Login, `/`).
# Nicht am DashboardController: /dashboard ist auch der Seitenleisten-Eintrag,
# und bei einer anderen Startseite (#1582) käme man dort gar nicht vorbei.
#
# Nur für Menschen (Agenten/API haben keinen Zweitfaktor) und nur, wenn der
# Nutzer die Einstellungsseite überhaupt öffnen darf — sie hängt am Recht
# „Actor lesen"; ohne dieses Recht führte die Umleitung auf eine 403-Seite.
module SicherheitZuerst
  extend ActiveSupport::Concern

  SICHERHEIT_STACK = "settings:security".freeze

  private

  def sicherheit_zuerst?(actor)
    actor.is_a?(HumanActor) && !actor.otp_enabled? &&
      AccessGate.can?(actor: actor, resource_type: "Actor", action: "read")
  end

  def sicherheit_zuerst_umleiten!
    session[:sicherheit_gezeigt] = true
    redirect_to settings_path(stack: SICHERHEIT_STACK)
  end
end
