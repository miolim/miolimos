# miolimOS – Phase 1 Seed-Daten
#
# Idempotent: Re-Run aktualisiert / ergänzt, statt Duplikate zu erzeugen.

puts "Seeding miolimOS Phase 1 data..."

# ─── Actors ─────────────────────────────────────────────────────────────────
# Admin-Nutzer für Self-Hosting aus ENV. KEIN hartkodiertes Default-Passwort:
# MIOLIMOS_ADMIN_PASSWORD setzen — sonst wird ein Zufallspasswort erzeugt und
# EINMALIG hier ausgegeben (danach im UI ändern).
# #806: Der erste Admin entsteht normalerweise im First-Run-Onboarding
# (/setup). Existiert schon ein Mensch, nutzen die Beispieldaten den —
# der ENV-Weg bleibt nur als Fallback für headless Setups.
admin = HumanActor.order(:id).first ||
        HumanActor.find_or_initialize_by(email: ENV.fetch("MIOLIMOS_ADMIN_EMAIL", "admin@example.com"))
admin.assign_attributes(name: ENV.fetch("MIOLIMOS_ADMIN_NAME", "Admin"), active: true)
if admin.password_digest.blank?
  from_env = ENV["MIOLIMOS_ADMIN_PASSWORD"].presence
  admin.password = from_env || SecureRandom.base58(20)
  puts(from_env ? "  ⚠ Admin-Passwort aus ENV gesetzt." : "  ⚠ Admin-Passwort ZUFÄLLIG erzeugt: #{admin.password}  (bitte notieren + im UI ändern)")
end
admin.save!
puts "  ✓ HumanActor: #{admin.name} <#{admin.email}>"

classifier = AgentActor.find_or_initialize_by(name: "Email Classifier")
classifier.assign_attributes(
  description: "Klassifiziert E-Mails und ordnet sie Themen zu",
  active: true
)
classifier.save!
puts "  ✓ AgentActor: #{classifier.name} (token: #{classifier.api_token[0, 8]}…)"

# ─── Team ───────────────────────────────────────────────────────────────────
team = Team.find_or_create_by!(name: "miolim") do |t|
  t.description = "Das miolim-Kernteam"
end

TeamMembership.find_or_create_by!(team: team, actor: admin) { |m| m.role = :owner }
TeamMembership.find_or_create_by!(team: team, actor: classifier) { |m| m.role = :member }
puts "  ✓ Team: #{team.name} (owner: #{admin.name}, member: #{classifier.name})"

# ─── Capabilities ───────────────────────────────────────────────────────────
# #806: Rechtematrix kommt aus CapabilityDefaults (eine Quelle für Seeds,
# capabilities:sync und das First-Run-Onboarding).
CapabilityDefaults.grant_full!(admin)

CapabilityDefaults::RESOURCE_TYPES.each do |resource|
  read_only = Capability.find_or_initialize_by(
    actor: classifier, resource_type: resource, effect: :allow
  )
  read_only.actions = %w[read]
  read_only.save!

  deny = Capability.find_or_initialize_by(
    actor: classifier, resource_type: resource, effect: :deny
  )
  deny.actions = %w[delete]
  deny.save!
end
puts "  ✓ Capabilities: Admin=Allow* | Classifier=ReadOnly+DenyDelete"

# ─── Beispiel-Themen ────────────────────────────────────────────────────────
topics_data = [
  { name: "Patent Ring Controller",  slug: "patent-ring",            description: "Entwicklung und Patentierung des Ring Controllers" },
  { name: "miolimOS Entwicklung",    slug: "miolimos-entwicklung",   description: "Entwicklung des miolimOS-Systems" },
  { name: "MPG Solar Betrieb",       slug: "mpg-solar",              description: "Betrieb der MPG-Solaranlage" }
]

example_topics = topics_data.map do |attrs|
  topic = Topic.find_or_initialize_by(slug: attrs[:slug])
  topic.assign_attributes(
    name:        attrs[:name],
    description: attrs[:description],
    status:      :active,
    template:    false,
    creator:     admin,
    team:        team
  )
  topic.save!
  topic
end
puts "  ✓ Themen: #{example_topics.map(&:name).join(', ')}"

# ─── Beispiel-Tasks pro Thema ───────────────────────────────────────────────
def ensure_task_in_topic(topic:, creator:, title:, priority: :normal, position: 1)
  task = Task.joins(:task_topics)
             .where(task_topics: { topic_id: topic.id })
             .where(title: title)
             .first
  task ||= Task.create!(title: title, creator: creator, priority: priority, status: :open)
  link = TaskTopic.find_or_initialize_by(task: task, topic: topic)
  link.position = position
  link.save!
  task
end

patent   = example_topics.find { |t| t.slug == "patent-ring" }
miolimos = example_topics.find { |t| t.slug == "miolimos-entwicklung" }
mpg      = example_topics.find { |t| t.slug == "mpg-solar" }

ensure_task_in_topic(topic: patent,   creator: admin, title: "Kostenanalyse Ring Controller",  priority: :high,   position: 1)
ensure_task_in_topic(topic: patent,   creator: admin, title: "Patentanwalt kontaktieren",       priority: :normal, position: 2)
ensure_task_in_topic(topic: miolimos, creator: admin, title: "Phase 1 Fundament fertigstellen", priority: :urgent, position: 1)
ensure_task_in_topic(topic: miolimos, creator: admin, title: "Phase 2 Wissen planen",           priority: :normal, position: 2)
ensure_task_in_topic(topic: mpg,      creator: admin, title: "Monatliche Ertragsauswertung",    priority: :normal, position: 1)

puts "  ✓ Beispiel-Tasks in Themen verknüpft"

# ─── Beispiel-Wartepunkte (Awaitings als eigene Entität) ────────────────────
def ensure_awaiting(title:, creator:, follow_up_at:, topic:)
  existing = Awaiting.find_by(title: title)
  awaiting = existing || Awaiting.create!(
    title:        title,
    creator:      creator,
    follow_up_at: follow_up_at
  )
  AwaitingTopic.find_or_create_by!(awaiting: awaiting, topic: topic)
  awaiting
end

ensure_awaiting(
  title:        "Rückmeldung von Patentanwalt zum Entwurf",
  creator:      admin,
  follow_up_at: 5.days.ago.to_date,
  topic:        patent
)
ensure_awaiting(
  title:        "Team-Feedback zur Phase-2-Demo",
  creator:      admin,
  follow_up_at: 2.days.from_now.to_date,
  topic:        miolimos
)
ensure_awaiting(
  title:        "Bestätigung des Netzbetreibers zur Einspeisung",
  creator:      admin,
  follow_up_at: 14.days.from_now.to_date,
  topic:        mpg
)
puts "  ✓ Beispiel-Wartepunkte angelegt (overdue, due_soon, future)"

# ─── Template: Neue PV-Anlage ───────────────────────────────────────────────
template = Topic.find_or_initialize_by(slug: "neue-pv-anlage-template")
template.assign_attributes(
  name:        "Neue PV-Anlage",
  description: "Template für den kompletten Prozess einer neuen PV-Anlage",
  status:      :active,
  template:    true,
  creator:     admin,
  team:        team
)
template.save!

template_task_definitions = [
  { title: "Standortbesichtigung",  priority: :high,   position: 1 },
  { title: "Angebot erstellen",     priority: :high,   position: 2 },
  { title: "Vertrag abschließen",   priority: :normal, position: 3 },
  { title: "Anlage installieren",   priority: :high,   position: 4 },
  { title: "Inbetriebnahme",        priority: :normal, position: 5 }
]

template_tasks = template_task_definitions.map do |defn|
  task = Task.joins(:task_topics)
             .where(task_topics: { topic_id: template.id })
             .where(title: defn[:title])
             .first
  task ||= Task.create!(
    title:    defn[:title],
    creator:  admin,
    priority: defn[:priority],
    status:   :open
  )
  link = TaskTopic.find_or_initialize_by(task: task, topic: template)
  link.position = defn[:position]
  link.save!
  task
end

# Jede Aufgabe hängt von der vorhergehenden ab (finish_to_start-Kette)
template_tasks.each_cons(2) do |pred, succ|
  TaskDependency.find_or_create_by!(predecessor: pred, successor: succ) do |dep|
    dep.dependency_type = :finish_to_start
  end
end

puts "  ✓ Template: #{template.name} mit #{template_tasks.size} Tasks und #{template_tasks.size - 1} Abhängigkeiten"

# ─── Beispiel-Wissensartefakte (Phase 2) ────────────────────────────────────
if defined?(KnowledgeItem)
  note_title     = "Patent Ring Controller – Architektur-Notiz"
  ai_chat_title  = "Claude-Chat – Ring Controller Kostenanalyse"

  existing_note = KnowledgeItem.find_by(title: note_title)
  unless existing_note
    FileProxy.create(
      actor:     admin,
      title:     note_title,
      item_type: :note,
      content:   <<~MD,
        Notiz zur Architektur des Ring Controllers.

        Detaillierte Kostenabschätzung siehe
        [[#{ai_chat_title}#Kostenanalyse]] – dort haben wir mit
        Claude die Komponenten durchgerechnet.
      MD
      topics:    ["patent-ring"],
      contacts:  [],
      tags:      ["architektur"]
    )
    puts "  ✓ KnowledgeItem (Note): #{note_title}"
  else
    puts "  · KnowledgeItem (Note) existiert bereits: #{note_title}"
  end

  existing_chat = KnowledgeItem.find_by(title: ai_chat_title)
  unless existing_chat
    FileProxy.create(
      actor:     admin,
      title:     ai_chat_title,
      item_type: :abstract,
      content:   <<~MD,
        Auszug aus einem Claude-Chat vom #{Date.today.iso8601}.

        ## Kostenanalyse

        Materialien, Fertigung und Zertifizierung grob aufgeschlüsselt.
        Kontext siehe [[#{note_title}]].

        ## Offene Punkte

        - Prüfen: Alternativen zum Ringmagneten
        - Rücksprache mit Patentanwalt
      MD
      topics:    ["patent-ring"],
      contacts:  [],
      tags:      ["kosten", "chat"]
    )
    puts "  ✓ KnowledgeItem (AI-Chat): #{ai_chat_title}"
  else
    puts "  · KnowledgeItem (AI-Chat) existiert bereits: #{ai_chat_title}"
  end

  # Nach dem Anlegen neu indizieren, damit Wikilink-Referenzen aufgelöst werden
  stats = KnowledgeIndexer.run
  puts "  ✓ Reindex: scanned=#{stats.scanned} created=#{stats.created} updated=#{stats.updated} " \
       "unchanged=#{stats.unchanged} references=#{stats.references}"
end

puts "Seed abgeschlossen."
