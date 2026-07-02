require "test_helper"

class AgentMentionsTest < ActiveSupport::TestCase
  setup do
    @hans  = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    @agent = AgentActor.create!(name: "mb-#{SecureRandom.hex(3)}", description: "t",
                                email: "mb-#{SecureRandom.hex(3)}@test.local")
    grant(@agent, "KnowledgeItem", %w[read create update])
  end

  def reply_on(parent, by:, body:)
    r = FileProxy.create(actor: by, title: "Reply #{SecureRandom.hex(3)}", item_type: :reply, content: body)
    r.update!(title: nil, parent_type: "KnowledgeItem", parent_uuid: parent.uuid, published_at: Time.current)
    r
  end

  test "a reply @-mentioning the agent is pending until the agent answers on the same KI" do
    with_isolated_miolimos_base do
      ki = FileProxy.create(actor: @hans, title: "Disk-KI", item_type: :note, content: "Gedanke.")
      reply_on(ki, by: @hans, body: "@#{@agent.name.parameterize} Was meinst Du?")

      assert_equal 1, AgentMentions.count_for(@agent), "mention should be pending"

      # Agent antwortet am selben KI → nicht mehr offen
      sleep 0.01
      reply_on(ki, by: @agent, body: "Meine Antwort.")
      assert_equal 0, AgentMentions.count_for(@agent), "answered mention should drop out"
    end
  end

  # #587: @-Mention im BODY einer normalen Notiz (kein Reply, published_at
  # nil) zählt jetzt auch — und gilt als beantwortet, sobald der Agent
  # auf DIESES KI antwortet.
  test "a body mention in a plain note is pending and answered by a reply on it" do
    with_isolated_miolimos_base do
      ki = FileProxy.create(actor: @hans, title: "Beratungsnotiz",
                            item_type: :note,
                            content: "Ist das valide, @#{@agent.name.parameterize}?")
      assert_equal 1, AgentMentions.count_for(@agent), "body mention should be pending"
      pending = AgentMentions.pending_for(@agent).first
      assert_equal "note", pending.item_type

      sleep 0.01
      reply_on(ki, by: @agent, body: "Einschätzung folgt.")
      assert_equal 0, AgentMentions.count_for(@agent), "reply on the note should answer it"
    end
  end

  # #587: der Body-Mention-Save pokt den Agenten (Flag inbox_run_requested_at);
  # wiederholte Edits und Selbst-Mentions poken nicht.
  test "saving a note with a fresh agent mention pokes the agent once" do
    with_isolated_miolimos_base do
      assert_nil @agent.reload.inbox_run_requested_at
      ki = FileProxy.create(actor: @hans, title: "Poke-Notiz",
                            item_type: :note,
                            content: "Bitte übernehmen, @#{@agent.name.parameterize}!")
      refute_nil @agent.reload.inbox_run_requested_at, "fresh mention should poke"

      # Edit OHNE neue Mention pokt nicht erneut
      @agent.update_column(:inbox_run_requested_at, nil)
      FileProxy.update(actor: @hans, knowledge_item: ki,
                       content: "Bitte übernehmen, @#{@agent.name.parameterize}! (ergänzt)")
      assert_nil @agent.reload.inbox_run_requested_at, "unchanged mention must not re-poke"

      # Selbst-Mention pokt nicht
      FileProxy.create(actor: @agent, title: "Selbstnotiz", item_type: :note,
                       content: "Notiz an mich, @#{@agent.name.parameterize}.")
      assert_nil @agent.reload.inbox_run_requested_at, "self mention must not poke"
    end
  end
end
