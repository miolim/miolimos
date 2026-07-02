require "application_system_test_case"

# #437 (Hans, 2026-06-01): Der Reply-Composer muss vor Datenverlust beim
# Wegnavigieren warnen. dirty-warn markiert das Form bei der ersten Eingabe
# als dirty; ein globaler Listener prompt dann bei turbo:before-visit /
# beforeunload. Diese Warnung war beim Comment->Reply-/CM6-Umbau verloren
# gegangen. Hier pruefen wir die Stimulus-Aufhaengung: Eingabe -> der
# umgebende Form-Wrapper traegt data-dirty="true".
class ReplyDirtyWarnTest < ApplicationSystemTestCase
  setup do
    @hans = create_human
    grant(@hans, "Task", %w[read create update])
    grant(@hans, "KnowledgeItem", %w[read create update])
    grant(@hans, "Topic", %w[read])
    @task = Task.create!(title: "Dirty-Warn Test-Task", creator: @hans, assignee: @hans)
    login_as(@hans)
  end

  test "reply composer wird bei Eingabe dirty (Wegnavigier-Warnung)" do
    visit "/tasks/#{@task.id}"

    form = find("form[data-controller~='dirty-warn'][action*='/replies']", wait: 10)
    assert_equal "false", form["data-dirty"], "Form startet sauber (nicht dirty)"

    # #801: Der Composer rendert inzwischen CM6 (Textarea versteckt) —
    # wir tippen in den echten CM6-Editor; dessen input-Events bubbeln
    # zum Form und müssen dirty-warn#mark auslösen (genau der Pfad, auf
    # dem die Warnung beim CM6-Umbau ursprünglich verloren ging).
    within form do
      find(".cm-content", wait: 10).send_keys("angefangene Antwort — darf nicht verloren gehen")
    end

    assert_equal "true", form["data-dirty"],
      "Eingabe muss das Form via dirty-warn#mark als dirty markieren"
  end
end
