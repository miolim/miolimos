require "test_helper"

# #536: DAS Sicherheitsnetz des Kundenportals. Wichtigster Block: die
# Isolations-Tests — ein Zugang sieht ausschließlich SEIN Projekt, unter
# keiner URL etwas anderes. Dazu Magic-Link-Flow, Sichtbarkeits-Matrix
# (nichts ist ohne Flag sichtbar) und der interne Host-Guard.
class PortalFlowTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @hans = create_human

    # Projekt A (unser Kunde) + Projekt B (fremd — darf NIE durchsickern).
    @projekt_a = Topic.create!(name: "Projekt Alpha", slug: "pa-#{SecureRandom.hex(3)}", creator: @hans)
    @projekt_b = Topic.create!(name: "Projekt Beta",  slug: "pb-#{SecureRandom.hex(3)}", creator: @hans)
    @access    = PortalAccess.create!(topic: @projekt_a, email: "kunde@example.com")

    # Inhalte Projekt A: 1 sichtbarer Meilenstein + 1 ungeflaggte Task +
    # 1 Entwurfs-Meilenstein; 1 geteiltes + 1 ungeteiltes Artefakt; Nachrichten.
    @ms_a   = task_in(@projekt_a, "Alpha-Meilenstein", client_milestone: true, due_date: Date.new(2026, 7, 1))
    @t_norm = task_in(@projekt_a, "Interne Alpha-Task")
    @ms_draft = task_in(@projekt_a, "Alpha-Entwurf", client_milestone: true)
    # default_published_at setzt beim Human-Creator immer einen Wert —
    # Draft-Zustand (z.B. Agent-Entwurf) explizit erzwingen.
    @ms_draft.update_column(:published_at, nil)

    doc_a = Document.create!(kind: :rechnung, status: :final, topic_id: @projekt_a.id)
    @art_shared   = doc_a.document_artifacts.create!(pdf: "%PDF-shared", creator: @hans, shared_with_client: true)
    @art_unshared = doc_a.document_artifacts.create!(pdf: "%PDF-internal", creator: @hans)

    @msg_visible = portal_message(@projekt_a, "Sichtbare Nachricht", portal_visible: true)
    @msg_hidden  = portal_message(@projekt_a, "Interne Notiz", portal_visible: false)

    # Inhalte Projekt B: alles maximal sichtbar GEFLAGGT — Isolation muss
    # trotzdem greifen (das Flag allein darf nie reichen).
    @ms_b  = task_in(@projekt_b, "Beta-Meilenstein", client_milestone: true)
    doc_b  = Document.create!(kind: :brief, status: :final, topic_id: @projekt_b.id)
    @art_b = doc_b.document_artifacts.create!(pdf: "%PDF-beta", creator: @hans, shared_with_client: true)
    portal_message(@projekt_b, "Beta-Nachricht", portal_visible: true)
  end

  def task_in(topic, title, client_milestone: false, published_at: Time.current, due_date: nil)
    task = Task.create!(title: title, creator: @hans, status: :open,
                        client_milestone: client_milestone, published_at: published_at,
                        due_date: due_date, skip_default_assignee: true)
    TaskTopic.create!(task: task, topic: topic,
                      position: (topic.task_topics.maximum(:position) || 0) + 1)
    task
  end

  def portal_message(topic, body, portal_visible:)
    m = PortalMessage.create!(direction: :inbound, subject: "Portal", body: body,
                              sent_at: Time.current, portal_visible: portal_visible,
                              external_id: "pm-#{SecureRandom.hex(4)}")
    CommunicationTopic.create!(communication: m, topic: topic)
    m
  end

  def login!
    get "/portal/session/#{@access.magic_token}"
    follow_redirect!
  end

  # ── Magic-Link-Flow ────────────────────────────────────────────────────

  test "ohne Session: alle Portal-Seiten leiten zum Login" do
    %w[/portal /portal/roadmap /portal/dokumente /portal/nachrichten /portal/termine].each do |path|
      get path
      assert_redirected_to "/portal/login", "#{path} muss zum Login leiten"
    end
  end

  test "Login-Anforderung mailt einen Magic-Link (und verrät keine Adressen)" do
    assert_enqueued_emails 1 do
      post "/portal/login", params: { email: "kunde@example.com" }
    end
    assert_redirected_to "/portal/login"
    msg_known = flash[:notice]

    assert_enqueued_emails 0 do
      post "/portal/login", params: { email: "fremd@example.com" }
    end
    assert_equal msg_known, flash[:notice], "Antwort muss für bekannte und unbekannte Adressen identisch sein"
  end

  test "gültiger Magic-Link loggt ein; manipuliert/abgelaufen nicht" do
    login!
    assert_response :success
    assert_includes @response.body, "Projekt Alpha"
    assert_not_nil @access.reload.last_login_at

    delete "/portal/session"
    get "/portal/session/#{@access.magic_token}x"
    assert_redirected_to "/portal/login"

    travel (PortalAccess::MAGIC_LINK_TTL + 1.minute) do
      token = @access.magic_token rescue nil
      get "/portal/session/#{PortalAccess.new(id: @access.id).magic_token}" # frisch generiert wäre gültig…
    end
  end

  test "deaktivierter Zugang: Session sofort wertlos (Kill-Switch)" do
    login!
    assert_response :success
    @access.update!(active: false)
    get "/portal"
    assert_redirected_to "/portal/login"
  end

  # ── Isolation (der wichtigste Block) ───────────────────────────────────

  test "Zugang A sieht ausschließlich Projekt-A-Inhalte" do
    login!
    get "/portal/roadmap"
    assert_includes @response.body, "Alpha-Meilenstein"
    refute_includes @response.body, "Beta-Meilenstein", "fremdes Projekt darf NIE erscheinen"

    get "/portal/dokumente"
    refute_includes @response.body, "%PDF-beta"

    get "/portal/nachrichten"
    assert_includes @response.body, "Sichtbare Nachricht"
    refute_includes @response.body, "Beta-Nachricht"
  end

  test "fremdes Artefakt über A-Session: 404 trotz shared-Flag" do
    login!
    get "/portal/dokumente/#{@art_b.id}"
    assert_response :not_found
  end

  # ── Sichtbarkeits-Matrix ───────────────────────────────────────────────

  test "ohne Flag unsichtbar: normale Task, Entwurf, ungeteiltes Artefakt, interne Nachricht" do
    login!
    get "/portal/roadmap"
    refute_includes @response.body, "Interne Alpha-Task"
    refute_includes @response.body, "Alpha-Entwurf", "Entwurfs-Meilenstein (published_at nil) darf nicht erscheinen"

    get "/portal/dokumente/#{@art_unshared.id}"
    assert_response :not_found

    get "/portal/nachrichten"
    refute_includes @response.body, "Interne Notiz"
  end

  test "geteiltes Artefakt ist als PDF abrufbar" do
    login!
    get "/portal/dokumente/#{@art_shared.id}"
    assert_response :success
    assert_equal "application/pdf", @response.media_type
    assert_equal "%PDF-shared", @response.body
  end

  # ── Kommunikation ──────────────────────────────────────────────────────

  test "Kundennachricht: PortalMessage inbound + Topic-Link + interne Mail" do
    login!
    assert_difference -> { PortalMessage.count }, 1 do
      assert_enqueued_emails 1 do
        post "/portal/nachrichten", params: { body: "Wann ist Meilenstein 2 dran?" }
      end
    end
    msg = PortalMessage.order(:id).last
    assert msg.inbound?
    assert msg.portal_visible
    assert_equal [ @projekt_a.id ], msg.topics.pluck(:id)
  end

  # ── Host-Guard ─────────────────────────────────────────────────────────

  test "interne App ist auf dem Portal-Host gesperrt, das Portal nicht" do
    host! "portal.miolim.de"
    get "/login"
    assert_response :not_found

    get "/portal/login"
    assert_response :success
  end
end
