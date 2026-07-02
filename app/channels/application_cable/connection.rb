# #232 Phase 0: Action-Cable-Connection. Turbo-Streams signiert seine
# Stream-Namen selbst (turbo-rails), daher braucht der reine Live-Update-
# Use-Case keine eigene Identifikation hier. Falls wir spaeter pro-Actor
# autorisierte Channels wollen, kommt das `identified_by`-Setup hierher.
module ApplicationCable
  class Connection < ActionCable::Connection::Base
  end
end
