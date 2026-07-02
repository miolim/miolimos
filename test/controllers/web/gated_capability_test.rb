require "test_helper"

# #564: Sicherheits-Invariante des Gated-Concerns. Vorher lief jede unbekannte
# Custom-Action mit "read" (fail-open) — 35 mutierende Actions waren mit
# Lese-Capability erreichbar. Jetzt gilt: mutierendes HTTP-Verb → mindestens
# update, außer der Controller deklariert die Lese-Semantik EXPLIZIT.
# Dieser Test friert beides ein: den Default und die Ausnahmenliste.
class GatedCapabilityTest < ActionDispatch::IntegrationTest
  # Bewusste Ausnahmen: POST/PATCH mit Lese- bzw. Selbst-Semantik.
  # Neue Einträge hier nur mit Begründung im Controller-Override.
  ALLOWED_READ_MUTATIONS = %w[
    dashboard#mark_read
    knowledge_items#resolve
    knowledge_items#request_entity_import
    knowledge_items#start_wikilink_research
    knowledge_stack#toggle_pin
    stack#resolve
  ].freeze

  CRUD = %w[index show new create edit update destroy].freeze

  test "keine mutierende Route läuft implizit mit read-Capability" do
    offenders = []
    Rails.application.routes.routes.each do |r|
      ctrl, act = r.defaults[:controller], r.defaults[:action]
      next unless ctrl && act
      next unless r.verb.to_s =~ /POST|PATCH|PUT|DELETE/
      next if CRUD.include?(act)
      klass = begin
        "#{ctrl.camelize}Controller".constantize
      rescue NameError
        next
      end
      next unless klass.include?(Gated)

      inst = klass.new
      inst.define_singleton_method(:action_name) { act }
      fake_request = Struct.new(:get?, :head?).new(false, false)
      inst.define_singleton_method(:request) { fake_request }
      cap = inst.send(:controller_action_to_capability)

      key = "#{ctrl}##{act}"
      offenders << key if cap == "read" && !ALLOWED_READ_MUTATIONS.include?(key)
    end
    assert_empty offenders.uniq.sort,
      "Mutierende Actions mit read-Capability (Override ergänzen oder Ausnahme begründen): #{offenders.uniq.sort.join(', ')}"
  end

  test "Read-only-Actor bekommt 403 auf mutierender Custom-Action" do
    reader = create_human
    reader.update!(password: "secretsecret")
    grant(reader, "Task", %w[read])
    task = create_task(creator: reader)
    post "/login", params: { email: reader.email, password: "secretsecret" }

    post "/tasks/#{task.id}/publish"
    assert_response :forbidden
  end

  test "KnowledgeItems-ACTION_CAPABILITIES bleibt wie deklariert" do
    expected = {
      "restore"                 => "update",
      "identifiers"             => "update",
      "addresses"               => "update",
      "complete_from_url"       => "update",
      "trash"                   => "read",
      "resolve"                 => "read",
      "wikilink_create"         => "create",
      "request_entity_import"   => "read",
      "start_wikilink_research" => "read"
    }
    assert_equal expected, KnowledgeItemsController::ACTION_CAPABILITIES
  end
end
