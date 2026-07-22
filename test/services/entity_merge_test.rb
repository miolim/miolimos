require "test_helper"

# #1075: Voller Merge zweier Person-/Org-KIs — Daten und Verweise wandern
# zum Ziel, die Quelle geht in den Papierkorb, ihr Titel wird Alias.
class EntityMergeTest < ActiveSupport::TestCase
  include ActionDispatch::TestProcess

  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
  end

  def create_person(title, content: "")
    FileProxy.create(actor: @hans, title: title, item_type: :person, content: content)
  end

  def create_bare_ki(title, item_type: :note)
    KnowledgeItem.create!(uuid: SecureRandom.uuid, title: title,
                         item_type: item_type, creator_id: @hans.id,
                         file_path: "kb/#{SecureRandom.hex(4)}.md",
                         content_hash: SecureRandom.hex(8))
  end

  test "Kontaktpunkte wandern, Duplikate werden verworfen" do
    with_isolated_miolimos_base do
      source = create_person("Stocker")
      target = create_person("Angela Stocker")
      source.contact_points.create!(kind: "email", value: "stocker@faro-immo.de")
      source.contact_points.create!(kind: "email", value: "gemeinsam@example.com")
      target.contact_points.create!(kind: "email", value: "Gemeinsam@example.com")

      EntityMerge.merge!(source: source, target: target, actor: @hans)

      values = target.reload.contact_points.pluck(:value)
      assert_includes values, "stocker@faro-immo.de"
      assert_equal 1, values.grep(/gemeinsam/i).size
      assert_equal 0, ContactPoint.where(knowledge_item_uuid: source.uuid).count
    end
  end

  test "Adressen und Identifier wandern mit Dedup" do
    with_isolated_miolimos_base do
      source = create_person("Dublette")
      target = create_person("Original")
      source.postal_addresses.create!(line1: "Weg 1", postal_code: "12345", city: "Berlin")
      source.postal_addresses.create!(line1: "Allee 2", postal_code: "99999", city: "Bonn")
      target.postal_addresses.create!(line1: "weg 1", postal_code: "12345", city: "berlin")
      Identifier.create!(knowledge_item_uuid: source.uuid, label: "Kundennummer", value: "K-77")

      EntityMerge.merge!(source: source, target: target, actor: @hans)

      assert_equal 2, target.reload.postal_addresses.count
      assert_equal ["K-77"], Identifier.where(knowledge_item_uuid: target.uuid).pluck(:value)
    end
  end

  test "Mentions aus KIs, Tasks und Kommunikationen zeigen danach aufs Ziel" do
    with_isolated_miolimos_base do
      source = create_person("Stocker")
      target = create_person("Angela Stocker")
      note   = create_bare_ki("Notiz")

      KnowledgeItemMention.create!(knowledge_item_uuid: note.uuid, mentioned_uuid: source.uuid)
      task = Task.create!(title: "T", creator: @hans)
      TaskMention.create!(task_id: task.id, mentioned_uuid: source.uuid)
      comm = Communication.create!(direction: "inbound", subject: "Mail",
                                   external_id: "em-#{SecureRandom.hex(4)}")
      CommunicationMention.create!(communication: comm, mentioned_uuid: source.uuid, role: "recipient")
      # Ziel ist am selben Comm in derselben Rolle schon verlinkt → Dedup.
      comm2 = Communication.create!(direction: "inbound", subject: "Mail 2",
                                    external_id: "em-#{SecureRandom.hex(4)}")
      CommunicationMention.create!(communication: comm2, mentioned_uuid: source.uuid, role: "recipient")
      CommunicationMention.create!(communication: comm2, mentioned_uuid: target.uuid, role: "recipient")

      EntityMerge.merge!(source: source, target: target, actor: @hans)

      assert_equal [target.uuid], KnowledgeItemMention.where(knowledge_item_uuid: note.uuid).pluck(:mentioned_uuid)
      assert_equal [target.uuid], TaskMention.where(task_id: task.id).pluck(:mentioned_uuid)
      assert_equal [target.uuid], comm.communication_mentions.pluck(:mentioned_uuid)
      assert_equal [target.uuid], comm2.communication_mentions.pluck(:mentioned_uuid)
      assert_equal 1, comm2.communication_mentions.count
    end
  end

  test "Selbstbezuege werden verworfen statt umgehaengt" do
    with_isolated_miolimos_base do
      source = create_person("Stocker")
      target = create_person("Angela Stocker")
      # Ziel erwähnt die Quelle in seinem Body-Index → würde Selbst-Mention.
      KnowledgeItemMention.create!(knowledge_item_uuid: target.uuid, mentioned_uuid: source.uuid)
      Relationship.create!(from_uuid: source.uuid, to_uuid: target.uuid, kind: "Dublette von")

      EntityMerge.merge!(source: source, target: target, actor: @hans)

      assert_equal 0, KnowledgeItemMention.where(knowledge_item_uuid: target.uuid,
                                                 mentioned_uuid: target.uuid).count
      assert_equal 0, Relationship.where(from_uuid: target.uuid, to_uuid: target.uuid).count
    end
  end

  test "Quellen-Autorschaft wandert ohne Dubletten (Regression #516)" do
    with_isolated_miolimos_base do
      source = create_person("M. Mueller")
      target = create_person("Max Mueller")
      src_record = Source.create!(title: "Buch", slug: "buch-#{SecureRandom.hex(3)}",
                                  csl_type: Source::CSL_TYPES.first, creator_id: @hans.id)
      SourceCreator.create!(source: src_record, knowledge_item_uuid: source.uuid,
                            role: "author", identification: "provisional")

      EntityMerge.merge!(source: source, target: target, actor: @hans)

      assert_equal [target.uuid], src_record.source_creators.pluck(:knowledge_item_uuid)
    end
  end

  test "Alias, Stammdaten-Luecken, Body-Append und Papierkorb" do
    with_isolated_miolimos_base do
      source = create_person("Stocker", content: "Maklerin bei Faro.")
      source.update!(gender: "female", salutation: "Frau Stocker", first_name: "A.")
      source.update!(personally_known: true)
      target = create_person("Angela Stocker", content: "Kontakt aus Zuria-Projekt.")
      target.update!(first_name: "Angela")

      EntityMerge.merge!(source: source, target: target, actor: @hans)

      target.reload
      assert_includes target.aliases.to_a, "Stocker"
      assert_equal "Angela", target.first_name, "vorhandene Stammdaten bleiben"
      assert_equal "female", target.gender, "leere Stammdaten werden gefuellt"
      assert target.personally_known?
      assert_includes target.body, "Kontakt aus Zuria-Projekt."
      assert_includes target.body, "Aus „Stocker“ übernommen"
      assert_includes target.body, "Maklerin bei Faro."

      assert KnowledgeItem.with_discarded.find(source.uuid).discarded?
      assert_not File.exist?(FileProxy::BASE_PATH.join(source.file_path))
    end
  end

  test "Kinder-Verweise (Replies, parent_org) folgen zum Ziel" do
    with_isolated_miolimos_base do
      source = create_person("Alt GmbH")
      target = create_person("Neu GmbH")
      reply  = create_bare_ki("Antwort", item_type: :reply)
      reply.update!(parent_uuid: source.uuid, parent_type: "KnowledgeItem")
      employee = create_person("Mitarbeiterin")
      employee.update!(parent_org_uuid: source.uuid)

      EntityMerge.merge!(source: source, target: target, actor: @hans)

      assert_equal target.uuid, reply.reload.parent_uuid
      assert_equal target.uuid, employee.reload.parent_org_uuid
    end
  end

  test "verweigert Selbst-Merge und Nicht-Person-Typen" do
    with_isolated_miolimos_base do
      person = create_person("P")
      note   = create_bare_ki("N")
      assert_raises(EntityMerge::Error) do
        EntityMerge.merge!(source: person, target: person, actor: @hans)
      end
      assert_raises(EntityMerge::Error) do
        EntityMerge.merge!(source: note, target: person, actor: @hans)
      end
    end
  end
end
