namespace :capabilities do
  # Idempotent: stellt sicher, dass jeder Actor, der bereits Rechte auf
  # Task hat, auch Rechte auf alle neuen Resource-Types bekommt. Safe in
  # Produktion bei jedem Deploy laufen zu lassen — erzeugt keine Example-
  # Daten, erweitert nur Capabilities für neue Models.
  #
  # Rechtsmatrix:
  #   HumanActors           → read/create/update/delete (Vollrechte)
  #   Builder-Agents        → read/create/update/delete (commit/deploy)
  #   andere AgentActors    → read/create/update (kein delete — opt-in
  #                           pro Agent via Settings-Form)
  #
  # Vorher war "andere Agents = read-only", aber sobald ein Agent (wie
  # der Researcher, #155) eigene KIs/Sources/Tasks anlegen soll, ist das
  # zu restriktiv. Default-Schema entspricht jetzt
  # `AgentActor#grant_default_capabilities!` — write yes, delete no.
  desc "Sync capabilities across all resource types for existing allowed actors"
  task sync: :environment do
    resource_types = %w[Task Awaiting Contact Topic KnowledgeItem Communication Actor OauthCredential Team Source InboxItem ActorView ActivityEvent Document TimeEntry Event]
    human_actions  = %w[read create update delete]
    agent_actions  = %w[read create update]

    Actor.find_each do |actor|
      # Wir leiten "dieser Actor soll allow-Rechte kriegen" vom Vorhandensein
      # einer bestehenden Task-allow-Capability ab. Neu angelegte Actors ohne
      # Berechtigung werden also nicht versehentlich aufgerüstet.
      next unless actor.capabilities.where(resource_type: "Task", effect: :allow).exists?

      # Builder-Agents (Naming-Convention `*_builder@…`) bekommen
      # zusätzlich `delete`, weil sie aus dem Inbox-Workflow heraus
      # auch löschen müssen (z.B. Test-Tasks aufräumen).
      is_builder = actor.is_a?(AgentActor) && actor.email.to_s.include?("_builder@")
      actions    = if actor.is_a?(HumanActor) || is_builder
                     human_actions
                   else
                     agent_actions
                   end

      resource_types.each do |rt|
        cap = Capability.find_or_initialize_by(actor: actor, resource_type: rt, effect: :allow)
        next if cap.actions == actions
        cap.actions = actions
        cap.save!
        puts "  ✓ #{actor.class.name}##{actor.id} #{actor.name}: #{rt} → #{actions.inspect}"
      end
    end
  end
end
