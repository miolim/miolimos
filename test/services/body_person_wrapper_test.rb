require "test_helper"

# #655: Selektion als Personen-Wikilink ([[@Name]]) im Block.
class BodyPersonWrapperTest < ActiveSupport::TestCase
  setup do
    @hans = HumanActor.create!(name: "Hans", email: "hans-bpw-#{SecureRandom.hex(3)}@t.local",
                               password: "secretsecret")
    grant(@hans, "KnowledgeItem", %w[read create update])
    grant(@hans, "Task", %w[read create update])
  end

  test "wrappt den Namen im adressierten Block als [[@Name]]" do
    with_isolated_miolimos_base do
      ki = FileProxy.create(actor: @hans, title: "Interview-Notiz", item_type: :note,
                            content: "Erster Absatz über Glenn Whale.\n\nZweiter Absatz: Audrey Tang sagt Dinge. ^abc12345")

      BodyPersonWrapper.call(item: ki, actor: @hans, anchor: "abc12345",
                             selected_text: "Audrey Tang")
      ki.reload
      assert_includes ki.body, "[[@Audrey Tang]] sagt Dinge."
      assert_includes ki.body, "über Glenn Whale."   # anderer Block unangetastet
    end
  end

  test "Task-Description funktioniert; Fehlerfälle sauber" do
    task = Task.create!(title: "T", creator: @hans,
                        description: "Im Gespräch mit Glenn Whale ging es um Ringe.")
    BodyPersonWrapper.call(item: task, actor: @hans, anchor: "block-1",
                           selected_text: "Glenn Whale")
    assert_includes task.reload.description, "[[@Glenn Whale]]"

    err = assert_raises(BodyPersonWrapper::Error) do
      BodyPersonWrapper.call(item: task, actor: @hans, anchor: "block-1",
                             selected_text: "Glenn Whale")
    end
    assert_includes err.message, "schon ein Wikilink"

    err = assert_raises(BodyPersonWrapper::Error) do
      BodyPersonWrapper.call(item: task, actor: @hans, anchor: "block-1",
                             selected_text: "Nicht Vorhanden")
    end
    assert_includes err.message, "nicht gefunden"
  end

  # #655 v2: DOM-Block-Nummern und Quell-Blöcke können divergieren —
  # eindeutiger Treffer im Ganz-Body rettet den Wrap; Umbruch in der
  # Quelle (Selektion hat Space) wird toleriert.
  test "Fallback: falscher Block-Index + Quell-Zeilenumbruch im Namen" do
    task = Task.create!(title: "T2", creator: @hans,
                        description: "Absatz eins.\n\nGespräch mit Glenn\nWhale über Governance.")
    BodyPersonWrapper.call(item: task, actor: @hans, anchor: "block-99",
                           selected_text: "Glenn Whale")
    assert_includes task.reload.description, "[[@Glenn Whale]] über Governance."
  end

  test "Mehrdeutig ohne Block-Treffer → klare Fehlermeldung" do
    task = Task.create!(title: "T3", creator: @hans,
                        description: "Anna Beispiel hier.\n\nAnna Beispiel dort.")
    err = assert_raises(BodyPersonWrapper::Error) do
      BodyPersonWrapper.call(item: task, actor: @hans, anchor: "block-99",
                             selected_text: "Anna Beispiel")
    end
    assert_includes err.message, "2×"
  end
end
