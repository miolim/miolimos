require "application_system_test_case"

# #1653 (Hans): „Mir scheint es so, dass in letzter Zeit bei Antworten durch den
# Agenten die Card nicht mehr automatisch aktualisiert wird, sondern dass man
# aktiv einen Refresh machen muss."
#
# Auf Produktion nachgemessen: Der Live-Weg (#232) trägt — solange die
# Verbindung steht. Verpasst wird, was WÄHREND einer Unterbrechung gesendet
# wird; ActionCable spielt nichts nach. Unterbrechungen sind Alltag: jeder
# Deploy startet den Server neu, dazu Ruhezustand und Netzwechsel.
#
# Der Test stellt genau das nach: Die Antwort entsteht, ohne dass ein
# Live-Update ankommt (im Testumfeld stellt der Cable-Adapter nichts zu — das
# IST die Unterbrechung). Dann wird eine Wiederverbindung simuliert, und die
# Liste muss den Stand von selbst nachholen.
class LiveResync1653Test < ApplicationSystemTestCase
  setup do
    @hans = create_human
    %w[Task KnowledgeItem].each { |rt| grant(@hans, rt, %w[read create update]) }
    login_as(@hans)
    @task = Task.create!(title: "Antwort-Aufgabe", creator: @hans, assignee: @hans, status: :open)
  end

  def antworten_im_dom
    page.evaluate_script(
      "document.querySelectorAll(\"#task_replies_list_#{@task.id} li\").length"
    )
  end

  def zaehler
    page.evaluate_script(
      "(document.querySelector('#task_replies_count_#{@task.id}')?.textContent || '').trim()"
    )
  end

  # Der Agent postet, während die Verbindung weg ist: dieselbe Reply-KI wie im
  # API-Pfad (Api::V1::TaskCommentsController) — aber OHNE Broadcast, denn
  # genau das ist die Unterbrechung. Erst als Entwurf anlegen (Entwürfe
  # broadcasten bewusst nicht), dann per update_columns veröffentlichen: das
  # geht an den Callbacks vorbei, es geht also nichts raus.
  #
  # Der Cable-Adapter im Testumfeld stellt lokal ZU — ein einfaches update!
  # würde die Antwort live ausliefern und die Lücke gar nicht nachstellen.
  def agent_antwortet!(text)
    reply = FileProxy.create(actor: @hans, title: "Reply #{SecureRandom.hex(3)}", item_type: :reply,
                             content: text, topics: [], contacts: [], tags: [])
    reply.update_columns(title: nil, parent_type: "Task", parent_id_int: @task.id,
                         published_at: Time.current)
  end

  # Verbindung weg und wieder da — genau die Umschaltung, die der
  # turbo-cable-stream-source im Browser vornimmt.
  def wiederverbinden!
    # Wie im Browser: Die Verbindung STAND, brach ab und kommt zurück. Ein
    # unbekannter Anfangszustand zählt bewusst nicht als Wiederverbindung.
    page.execute_script(<<~JS)
      document.querySelectorAll("turbo-cable-stream-source").forEach(el => {
        el.setAttribute("connected", "")
        setTimeout(() => el.removeAttribute("connected"), 50)
        setTimeout(() => el.setAttribute("connected", ""), 150)
      })
    JS
  end

  test "eine während der Unterbrechung gepostete Antwort wird nachgeholt" do
    with_isolated_miolimos_base do
      visit "/tasks?stack=task:#{@task.id}"
      assert_selector "#task_replies_list_frame_#{@task.id}", wait: 10
      assert_equal 0, antworten_im_dom, "zu Beginn keine Antwort"

      agent_antwortet!("Antwort aus der Verbindungslücke")
      sleep 0.5
      assert_equal 0, antworten_im_dom,
                   "Vorbedingung: ohne Zustellung zeigt die Card sie noch nicht"

      wiederverbinden!

      assert_text "Antwort aus der Verbindungslücke", wait: 10
      assert_operator antworten_im_dom, :>, 0
      # Wartend prüfen: Der Zähler wird erst beim turbo:frame-load gesetzt,
      # also einen Wimpernschlag nach dem Text.
      assert_selector "#task_replies_count_#{@task.id}", text: "· 1", wait: 5
      assert_equal "· 1", zaehler, "der Zähler zieht mit, obwohl er außerhalb des Frames steht"
    end
  end

  test "der erste Verbindungsaufbau lädt nicht doppelt nach" do
    with_isolated_miolimos_base do
      visit "/tasks?stack=task:#{@task.id}"
      assert_selector "#task_replies_list_frame_#{@task.id}", wait: 10

      # Nur VERBINDEN (ohne vorherige Trennung) darf kein Nachladen auslösen.
      page.execute_script(<<~JS)
        window.__ladezaehler = 0
        document.addEventListener("turbo:frame-load", () => { window.__ladezaehler++ })
        document.querySelectorAll("turbo-cable-stream-source").forEach(el => el.setAttribute("connected", ""))
      JS
      sleep 1.5

      assert_equal 0, page.evaluate_script("window.__ladezaehler"),
                   "ohne vorherige Trennung wird nichts nachgeladen"
    end
  end
end
