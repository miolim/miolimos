# #1582 (Hans): „Man soll festlegen können, welcher Stack beim Programmstart
# als erstes angezeigt wird. Im Moment ist es standardmäßig das Dashboard,
# aber das soll man frei wählen können."
#
# `/` landet hier und leitet zur Startseite aus den Vorlieben weiter. Das ist
# die EINE Stelle für „was passiert beim Start" — der Login ohne Deep-Link
# nutzt dasselbe Ziel (SessionsController#finish_login). Wer beim Start etwas
# vorschalten will (etwa eine Sicherheits-Card ohne 2FA), hängt es hier ein,
# nicht an /dashboard: Das ist auch der Seitenleisten-Eintrag und darf nicht
# umleiten.
class StartController < ApplicationController
  # Reine Weiterleitung auf die eigene Vorliebe — das Ziel prüft seine Rechte
  # selbst. Ein Gate hier verlangte ein Recht, das nicht jeder hat, und `/`
  # endete für manche Nutzer in einer 403-Seite statt auf ihrer Startseite.
  skip_before_action :enforce_access_gate

  def show
    redirect_to helpers.start_stack_path(current_actor)
  end
end
