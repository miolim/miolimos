require "test_helper"

class KnowledgeItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-k-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    grant(@hans, "Topic",         %w[read])
    grant(@hans, "Contact",       %w[read])

    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  # #739 (Hans): Quick-Create ohne Titel — Platzhalter je item_type, an den
  # Stack appenden, Cursor ins Titelfeld (statt an der Pflicht zu scheitern).
  test "#739 Quick-Create Person ohne Titel legt Platzhalter an + fokussiert Titelfeld" do
    with_isolated_miolimos_base do
      assert_difference -> { KnowledgeItem.where(item_type: "person").count }, 1 do
        post "/knowledge_items",
             params: { quick_create: "1", item_type: "person", title: "" },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_response :ok
      ki = KnowledgeItem.where(item_type: "person").order(:created_at).last
      assert_equal "Neue Person", ki.title
      assert_includes @response.body, 'data-focus-after-add="title"'
      refute_includes @response.body, 'data-focus-after-add="content_edit"'
    end
  end

  test "PATCH /knowledge_items/:uuid mit in_stack=1 antwortet Stream auf knowledge_detail_<uuid>" do
    item = FileProxy.create(actor: @hans, title: "Stack-Save",
                            item_type: :note, content: "alt",
                            topics: [], contacts: [], tags: [])
    patch "/knowledge_items/#{item.uuid}",
          params: { content: "neu", in_stack: "1" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :ok
    # Stream zielt auf den eindeutigen Frame der Card, nicht auf den
    # generischen "knowledge_detail" — das ist die Bug-Fix-Garantie.
    assert_includes @response.body, %(target="knowledge_detail_#{item.uuid}")
    refute_includes @response.body, %(target="knowledge_detail")[0..-2] +
                    %(>)  # generic ID darf nicht als alleinstehender Target auftauchen
  end

  test "GET /knowledge_items/:uuid/card returns stack-card fragment" do
    item = FileProxy.create(actor: @hans, title: "Notiz im Stack",
                            item_type: :note, content: "Hallo",
                            topics: [], contacts: [], tags: [])
    get "/knowledge_items/#{item.uuid}/card"
    assert_response :success
    # Stack-Card-Markup vorhanden, kein Layout-Drumherum
    assert_includes @response.body, %(data-uuid="#{item.uuid}")
    assert_includes @response.body, "stack-card"
    refute_includes @response.body, "<html"
    refute_includes @response.body, "id=\"toast_stack\""
  end

  # #770 (Hans): Das Editieren des KI-Bodys muss — wie die Aufgaben-
  # Beschreibung (#560) — den Auto-Timer dieser KI starten. Das Body-Formular
  # trägt dafür die reply-timer-Verdrahtung mit subject_type=KnowledgeItem.
  test "KI-Body-Formular trägt die Auto-Timer-Verdrahtung (#770)" do
    item = FileProxy.create(actor: @hans, title: "Body mit Timer",
                            item_type: :note, content: "viel Text",
                            topics: [], contacts: [], tags: [])
    get "/knowledge_items/#{item.uuid}/edit"
    assert_response :success
    assert_includes @response.body, "reply-timer dirty-warn"
    assert_includes @response.body, %(data-reply-timer-subject-type-value="KnowledgeItem")
    assert_includes @response.body, %(data-reply-timer-subject-id-value="#{item.uuid}")
    assert_includes @response.body, "reply-timer#begin"
  end

  test "ungelöste Wikilinks rendern als klickbarer .wikilink-missing-Link" do
    src = FileProxy.create(actor: @hans, title: "Quelle",
                           item_type: :note,
                           content: "Verlinke [[Noch Nicht Existiert]]",
                           topics: [], contacts: [], tags: [])
    get "/knowledge_items/#{src.uuid}/card"
    assert_response :success
    assert_includes @response.body, "wikilink-missing"
    assert_includes @response.body, %(data-target-title="Noch Nicht Existiert")
    assert_includes @response.body, %(data-action="click->blade-stack#openMissing")
  end

  test "POST /knowledge_items/wikilink_create legt KI an + ist idempotent" do
    assert_difference -> { KnowledgeItem.count }, 1 do
      post "/knowledge_items/wikilink_create", params: { title: "Frische Notiz" }
    end
    json = JSON.parse(@response.body)
    assert json["uuid"]
    assert_equal "Frische Notiz", json["title"]

    # Zweiter Aufruf mit demselben Titel → kein neues Item
    assert_no_difference -> { KnowledgeItem.count } do
      post "/knowledge_items/wikilink_create", params: { title: "Frische Notiz" }
    end
    second = JSON.parse(@response.body)
    assert_equal json["uuid"], second["uuid"]
  end

  test "Wikilinks im gerenderten Body bekommen data-target-uuid + Stack-Action" do
    target = FileProxy.create(actor: @hans, title: "Ziel-Notiz",
                              item_type: :note, content: "x",
                              topics: [], contacts: [], tags: [])
    source = FileProxy.create(actor: @hans, title: "Quell-Notiz",
                              item_type: :note, content: "Siehe [[Ziel-Notiz]]",
                              topics: [], contacts: [], tags: [])
    get "/knowledge_items/#{source.uuid}/card"
    assert_response :success
    assert_includes @response.body, %(class="wikilink text-emerald-700 underline")
    assert_includes @response.body, %(data-target-uuid="#{target.uuid}")
    assert_includes @response.body, %(data-action="click->blade-stack#openInStack")
  end

  test "GET /knowledge_items mit ?stack=u1,u2 rendert beide Cards initial" do
    a = FileProxy.create(actor: @hans, title: "Stack-A", item_type: :note,
                         content: "x",
                         topics: [], contacts: [], tags: [])
    b = FileProxy.create(actor: @hans, title: "Stack-B", item_type: :note,
                         content: "y",
                         topics: [], contacts: [], tags: [])
    get "/knowledge_items?stack=#{a.uuid},#{b.uuid}"
    assert_response :success
    assert_includes @response.body, %(data-uuid="#{a.uuid}")
    assert_includes @response.body, %(data-uuid="#{b.uuid}")
  end

  test "GET /knowledge_items lists items" do
    FileProxy.create(actor: @hans, title: "Notiz-Alpha",
                     item_type: :note, content: "Inhalt",
                     topics: [], contacts: [], tags: [])
    get "/knowledge_items"
    assert_response :success
    assert_includes @response.body, "Notiz-Alpha"
  end

  # #257: Listen-Blade-Fragment fuers Sidebar-Plus — laedt @items selbst.
  test "GET /knowledge_items/list_card renders self-contained list blade" do
    FileProxy.create(actor: @hans, title: "Wissen-Beta",
                     item_type: :note, content: "x",
                     topics: [], contacts: [], tags: [])
    get "/knowledge_items/list_card"
    assert_response :success
    assert_match %r{data-uuid="list:knowledge_items"}, @response.body
    assert_includes @response.body, "Wissen-Beta"
    refute_match %r{<html}, @response.body
  end

  # #257 follow-up: Personen-Listen-Blade fuers Sidebar-Plus.
  test "GET /persons/list_card renders persons list blade" do
    FileProxy.create(actor: @hans, title: "Erika Musterfrau",
                     item_type: :person, content: "")
    FileProxy.create(actor: @hans, title: "Nur-Eine-Notiz",
                     item_type: :note, content: "x")
    get "/persons/list_card"
    assert_response :success
    assert_match %r{data-uuid="list:persons"}, @response.body
    assert_includes @response.body, "Erika Musterfrau"
    refute_includes @response.body, "Nur-Eine-Notiz"
    refute_match %r{<html}, @response.body
  end

  # #450 (Hans, 2026-06-01): Die Farb-Chips werden aus der UNGEFILTERTEN
  # Beschreibung gezaehlt — sonst fielen bei aktivem ?hl= die anderen
  # Farben auf 0 und ihre Chips verschwanden (additives Waehlen unmoeglich).
  test "GET /knowledge_items/:uuid — Highlight-Chips bleiben bei aktivem ?hl= stehen" do
    item = FileProxy.create(actor: @hans, title: "HL-Filter",
                            item_type: :note,
                            content: "Text mit ==rot|wichtig== und ==blau|egal==.\n",
                            topics: [], contacts: [], tags: [])
    get "/knowledge_items/#{item.uuid}"
    assert_response :success
    assert_includes @response.body, "rot: 1 Highlight"
    assert_includes @response.body, "blau: 1 Highlight"

    get "/knowledge_items/#{item.uuid}?hl=rot"
    assert_response :success
    assert_includes @response.body, "rot: 1 Highlight"
    assert_includes @response.body, "blau: 1 Highlight",
                    "andere Farb-Chips muessen bei aktivem Filter erhalten bleiben (#450)"
  end

  # #782 (Hans): Highlight-Filter läuft jetzt CLIENTSEITIG (gleicher Modus-
  # Button wie die Suche). Bei aktivem ?hl= rendert der Server den VOLLEN Body
  # (Kontext im DOM) und reicht die aktiven Farben an den reply-search-Controller.
  test "GET /knowledge_items/:uuid?hl= rendert vollen Body + Farben an Controller (#782)" do
    item = FileProxy.create(actor: @hans, title: "HL-Kontext", item_type: :note,
      content: "Erster Absatz ohne Marker.\n\nZweiter mit ==rot|wichtig==.\n\nDritter Absatz.\n",
      topics: [], contacts: [], tags: [])
    get "/knowledge_items/#{item.uuid}?hl=rot"
    assert_response :success
    # Voller Body: auch nicht-markierte Absätze sind da (Client filtert).
    assert_includes @response.body, "Erster Absatz ohne Marker"
    assert_includes @response.body, "Dritter Absatz"
    # Aktive Farbe geht an den Such-Controller.
    assert_match %r{reply-search-highlight-colors-value="[^"]*rot[^"]*"}, @response.body
    # NICHT mehr serverseitig auf bare Marks reduziert.
    refute_includes @response.body, "hl-filter-block"
  end

  # #451 (Hans, 2026-06-01): Nach einem Reply-Entwurf-Save bekommt das
  # Compose-Feld autofocus (damit der folgende Strg+Umschalt+Enter greift)
  # und der Entwurf einen per data-reply-publish auffindbaren Button.
  test "Reply-Entwurf-Save: Compose-Autofocus + auffindbarer Publish-Button" do
    item = FileProxy.create(actor: @hans, title: "Reply-Parent-Draft",
                            item_type: :note, content: "x",
                            topics: [], contacts: [], tags: [])
    post "/knowledge_items/#{item.uuid}/replies", params: { body: "Mein Entwurf", draft: "1" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes @response.body, 'data-cm6-editor-autofocus-value="true"'
    assert_includes @response.body, "data-reply-publish"
  end

  test "Reply-Senden (kein Entwurf): kein Compose-Autofocus" do
    item = FileProxy.create(actor: @hans, title: "Reply-Parent-Send",
                            item_type: :note, content: "x",
                            topics: [], contacts: [], tags: [])
    post "/knowledge_items/#{item.uuid}/replies", params: { body: "Direkt senden", draft: "" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes @response.body, 'data-cm6-editor-autofocus-value="false"'
  end

  test "GET /knowledge_items/:uuid renders 2-space-indented nested bullet list" do
    body = <<~MD
      # Test

      - top
        - nested
          - deep
    MD
    item = FileProxy.create(actor: @hans, title: "Liste",
                            item_type: :note, content: body,
                            topics: [], contacts: [], tags: [])
    get "/knowledge_items/#{item.uuid}"
    assert_response :success
    # Drei verschachtelte ul-Tags müssen vorhanden sein
    open_uls = @response.body.scan(/<ul[ >]/).size
    close_uls = @response.body.scan(/<\/ul>/).size
    assert open_uls >= 3, "expected ≥3 <ul> opens, got #{open_uls}"
    assert close_uls >= 3, "expected ≥3 </ul> closes, got #{close_uls}"
    assert_includes @response.body, "deep"
  end

  test "GET /knowledge_items?item_type=note filters" do
    FileProxy.create(actor: @hans, title: "Nur-Note",
                     item_type: :note, content: "N",
                     topics: [], contacts: [], tags: [])
    FileProxy.create(actor: @hans, title: "Chat-Eintrag",
                     item_type: :abstract, content: "C",
                     topics: [], contacts: [], tags: [])
    get "/knowledge_items", params: { item_type: "note" }
    assert_includes @response.body, "Nur-Note"
    refute_includes @response.body, "Chat-Eintrag"
  end

  test "GET /knowledge_items/suggest returns JSON" do
    FileProxy.create(actor: @hans, title: "Suggest-Me",
                     item_type: :note, content: ".",
                     topics: [], contacts: [], tags: [])
    get "/knowledge_items/suggest", params: { q: "Suggest" }
    assert_response :success
    body = JSON.parse(@response.body)
    assert body["items"].any? { |i| i["title"] == "Suggest-Me" }
  end

  # #667: `[[@Name`-Personen-Autocomplete — führendes @ strippen,
  # item_type-Filter auf Person/Org.
  test "suggest strippt @-Präfix und filtert auf Personen" do
    person = FileProxy.create(actor: @hans, title: "Audrey Tang", item_type: :person, content: ".")
    note   = FileProxy.create(actor: @hans, title: "Audrey Notiz", item_type: :note, content: ".")
    get "/knowledge_items/suggest", params: { q: "@Audrey", item_type: "person,organization" }
    assert_response :success
    titles = JSON.parse(@response.body)["items"].map { |i| i["title"] }
    assert_includes titles, "Audrey Tang"
    refute_includes titles, "Audrey Notiz", "Notiz darf nicht in der Personen-Auswahl auftauchen"
  end

  test "POST /knowledge_items creates item via FileProxy" do
    assert_difference -> { KnowledgeItem.count }, 1 do
      post "/knowledge_items", params: {
        title: "Neue Notiz X", item_type: "note", source: "manual",
        content: "Text", topics: "", contacts: "", tags: ""
      }
    end
  end

  # #827 (Hans): Blur-Autosave eines einzelnen Namensfelds (inline=1) darf
  # NICHT mit einem Detail-Frame-Replace antworten — der Replace überschrieb
  # das Nachbarfeld mitten im Tippen (Zeichen "verschwanden" abwechselnd).
  test "#827 PATCH mit inline=1 speichert, antwortet aber 204 ohne Detail-Replace" do
    with_isolated_miolimos_base do
      item = FileProxy.create(actor: @hans, title: "Mia Muster",
                              item_type: :person, content: "",
                              topics: [], contacts: [], tags: [])
      patch "/knowledge_items/#{item.uuid}",
            params: { first_name: "Mia", inline: "1", in_stack: "1" },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :no_content
      assert_empty @response.body
      assert_equal "Mia", item.reload.first_name
    end
  end

  test "#827 Person-Create ohne Namensfelder leitet Vor-/Nachname aus dem Titel ab" do
    with_isolated_miolimos_base do
      post "/knowledge_items", params: {
        title: "Max von Mustermann", item_type: "person", source: "manual",
        content: "", topics: "", contacts: "", tags: "", first_name: "", last_name: ""
      }
      ki = KnowledgeItem.persons.order(:created_at).last
      assert_equal "Max von",    ki.first_name
      assert_equal "Mustermann", ki.last_name
    end
  end

  test "#827 Person-Create mit Ein-Wort-Titel splittet nicht" do
    with_isolated_miolimos_base do
      post "/knowledge_items", params: {
        title: "Madonna", item_type: "person", source: "manual",
        content: "", topics: "", contacts: "", tags: ""
      }
      ki = KnowledgeItem.persons.order(:created_at).last
      assert_nil ki.first_name
      assert_nil ki.last_name
    end
  end

  test "#827 Person-Create mit Namensfeldern ohne Titel setzt den Titel zusammen" do
    with_isolated_miolimos_base do
      post "/knowledge_items",
           params: { quick_create: "1", item_type: "person", title: "",
                     first_name: "Erika", last_name: "Musterfrau" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      ki = KnowledgeItem.persons.order(:created_at).last
      assert_equal "Erika Musterfrau", ki.title
      assert_equal "Erika", ki.first_name
      assert_equal "Musterfrau", ki.last_name
    end
  end

  test "POST /knowledge_items/:uuid/restore reverses soft-delete" do
    item = FileProxy.create(actor: @hans, title: "Restore-Test",
                            item_type: :note, content: "x",
                            topics: [], contacts: [], tags: [])
    FileProxy.destroy(actor: @hans, knowledge_item: item)
    assert item.reload.discarded?

    post "/knowledge_items/#{item.uuid}/restore",
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    refute item.reload.discarded?
  end

  test "GET /knowledge_items/trash lists discarded items" do
    keep = FileProxy.create(actor: @hans, title: "Lebt",
                            item_type: :note, content: "x",
                            topics: [], contacts: [], tags: [])
    discarded = FileProxy.create(actor: @hans, title: "Trashed-K-9z9z",
                                 item_type: :note, content: "y",
                                 topics: [], contacts: [], tags: [])
    FileProxy.destroy(actor: @hans, knowledge_item: discarded)

    get "/knowledge_items/trash"
    assert_response :success
    assert_includes @response.body, "Trashed-K-9z9z"
    refute_includes @response.body, "Lebt"
  end

  test "DELETE /knowledge_items/:uuid destroys item and file" do
    item = FileProxy.create(actor: @hans, title: "Wegwerf",
                            item_type: :note, content: "x",
                            topics: [], contacts: [], tags: [])
    assert_difference -> { KnowledgeItem.count }, -1 do
      delete "/knowledge_items/#{item.uuid}"
    end
    assert_redirected_to knowledge_items_path
  end

  test "PATCH /knowledge_items/:uuid updates content" do
    item = FileProxy.create(actor: @hans, title: "Alt",
                            item_type: :note, content: "Alt",
                            topics: [], contacts: [], tags: [])
    patch "/knowledge_items/#{item.uuid}", params: {
      title: "Alt", content: "Neu", topics: "", contacts: "", tags: ""
    }
    assert_redirected_to knowledge_item_path(item.uuid)
  end

  # ─── Block-Anker / Counter-Icon ─────────────────────────────────

  test "Block mit ^anchor im Markdown bekommt entsprechende id und kein <span data-anchor>" do
    md = "Erste Zeile mit ^firstid\n\n- Liste ^listid"
    item = FileProxy.create(actor: @hans, title: "Anker-Test",
                            item_type: :note, content: md,
                            topics: [], contacts: [], tags: [])
    get "/knowledge_items/#{item.uuid}/card"
    assert_response :success
    assert_includes @response.body, %(id="firstid")
    assert_includes @response.body, %(id="listid")
    refute_includes @response.body, "data-anchor=", "Marker-Span muss durch Pass 1 entfernt sein"
  end

  test "Anker-Marker frisst keine Leerzeile zwischen Paragraph und Liste" do
    md = "URL ^topid\n\n- erstes ^aid\n- zweites ^bid"
    item = FileProxy.create(actor: @hans, title: "Listen-Spacing",
                            item_type: :note, content: md,
                            topics: [], contacts: [], tags: [])
    get "/knowledge_items/#{item.uuid}/card"
    assert_response :success
    # Markdown muss `<p>` und separates `<ul><li>` rendern, NICHT alles
    # in einem `<p>` mit `<br>`-Trennern
    assert_includes @response.body, "<ul"
    assert_includes @response.body, "<li"
  end

  test "anker-lose Blocks bekommen positionsbasierte block-N-IDs" do
    md = "Erster Absatz\n\nZweiter Absatz"
    item = FileProxy.create(actor: @hans, title: "Block-N",
                            item_type: :note, content: md,
                            topics: [], contacts: [], tags: [])
    get "/knowledge_items/#{item.uuid}/card"
    assert_includes @response.body, %(id="block-1")
    assert_includes @response.body, %(id="block-2")
  end

  test "POST /:uuid/ensure_anchor: bestehender Anker wird durchgereicht" do
    md = "Vorhanden ^abc"
    item = FileProxy.create(actor: @hans, title: "Anchor-Existing",
                            item_type: :note, content: md,
                            topics: [], contacts: [], tags: [])
    post "/knowledge_items/#{item.uuid}/ensure_anchor",
         params: { anchor: "abc" },
         headers: { "Accept" => "application/json" }
    assert_response :success
    assert_equal "abc", JSON.parse(@response.body)["anchor"]
  end

  test "POST /:uuid/ensure_anchor: block-N-Anfrage erzeugt neuen Anker am richtigen Block" do
    md = "Erster Absatz\n\nZweiter Absatz"
    item = FileProxy.create(actor: @hans, title: "Anchor-New",
                            item_type: :note, content: md,
                            topics: [], contacts: [], tags: [])
    post "/knowledge_items/#{item.uuid}/ensure_anchor",
         params: { anchor: "block-2" },
         headers: { "Accept" => "application/json" }
    assert_response :success
    new_anchor = JSON.parse(@response.body)["anchor"]
    # #466: Anker-Format vereinheitlicht -> ensure_anchor liefert 8-Hex.
    assert_match(/\A[a-f0-9]{8}\z/, new_anchor)

    # Source-Datei zeigt den neuen Anker an Zeile 2
    raw = FileProxy.read(actor: @hans, knowledge_item: item.reload)
    assert_includes raw.lines.find { |l| l.start_with?("Zweiter") }, "^#{new_anchor}"
    refute_match(/Erster Absatz \^/, raw)
  end

  test "POST /:uuid/ensure_anchor: bei Listen zählt jedes <li> als eigener Block" do
    md = "- erstes\n- zweites\n- drittes"
    item = FileProxy.create(actor: @hans, title: "Liste-Anchor",
                            item_type: :note, content: md,
                            topics: [], contacts: [], tags: [])
    post "/knowledge_items/#{item.uuid}/ensure_anchor",
         params: { anchor: "block-2" },
         headers: { "Accept" => "application/json" }
    new_anchor = JSON.parse(@response.body)["anchor"]
    raw = FileProxy.read(actor: @hans, knowledge_item: item.reload)
    assert_includes raw.lines.find { |l| l.start_with?("- zweites") }, "^#{new_anchor}"
    refute_match(/erstes \^/, raw)
    refute_match(/drittes \^/, raw)
  end

  test "POST /:uuid/ensure_anchor: anker-lose Indexierung überspringt anchored Blocks" do
    # Drei Blocks: 1 ohne Anker, 2 mit Anker, 3 ohne Anker.
    # block-2 im DOM ist der DRITTE Source-Block (zweite anker-lose Zeile).
    md = "Erster\n\nZweiter ^fixed\n\nDritter"
    item = FileProxy.create(actor: @hans, title: "Skip-Anchored",
                            item_type: :note, content: md,
                            topics: [], contacts: [], tags: [])
    post "/knowledge_items/#{item.uuid}/ensure_anchor",
         params: { anchor: "block-2" },
         headers: { "Accept" => "application/json" }
    new_anchor = JSON.parse(@response.body)["anchor"]
    raw = FileProxy.read(actor: @hans, knowledge_item: item.reload)
    assert_match(/Dritter \^#{new_anchor}/, raw)
    refute_match(/Erster \^/, raw)
  end

  test "POST /:uuid/comment_at: legt Comment-KI mit Wikilink + Reference an" do
    md = "Quelltext mit Anker ^source-block"
    item = FileProxy.create(actor: @hans, title: "Quelle",
                            item_type: :note, content: md,
                            topics: [], contacts: [], tags: [])
    assert_difference -> { KnowledgeItem.where(item_type: :comment).count }, 1 do
      assert_difference -> { KnowledgeItemReference.where(target_uuid: item.uuid, anchor_type: :block).count }, 1 do
        post "/knowledge_items/#{item.uuid}/comment_at",
             params: { anchor: "source-block" },
             headers: { "Accept" => "application/json" }
      end
    end
    assert_response :success
    data = JSON.parse(@response.body)
    assert data["uuid"]
    assert_equal "source-block", data["anchor"]

    comment = KnowledgeItem.find_by(uuid: data["uuid"])
    body = FileProxy.read(actor: @hans, knowledge_item: comment)
    assert_includes body, "[[#{item.uuid}^source-block|"
  end

  test "GET /:uuid/backlinks: liefert Quellen ohne soft-deleted Sources" do
    src = FileProxy.create(actor: @hans, title: "Quelle mit Anker",
                           item_type: :note,
                           content: "X ^myid",
                           topics: [], contacts: [], tags: [])
    post "/knowledge_items/#{src.uuid}/comment_at",
         params: { anchor: "myid" },
         headers: { "Accept" => "application/json" }
    comment_uuid_a = JSON.parse(@response.body)["uuid"]
    post "/knowledge_items/#{src.uuid}/comment_at",
         params: { anchor: "myid" },
         headers: { "Accept" => "application/json" }
    comment_uuid_b = JSON.parse(@response.body)["uuid"]

    # Soft-Delete den ersten Comment
    FileProxy.destroy(actor: @hans, knowledge_item: KnowledgeItem.find_by(uuid: comment_uuid_a))

    get "/knowledge_items/#{src.uuid}/backlinks",
        params: { anchor: "myid" },
        headers: { "Accept" => "application/json" }
    assert_response :success
    items = JSON.parse(@response.body)["items"]
    uuids = items.map { |i| i["uuid"] }
    refute_includes uuids, comment_uuid_a, "soft-deleted Comment darf nicht erscheinen"
    assert_includes uuids, comment_uuid_b
  end

  test "Counter-Icon zählt nur aktive Backlink-Quellen" do
    src = FileProxy.create(actor: @hans, title: "Counter-Filter",
                           item_type: :note,
                           content: "Z ^cnt",
                           topics: [], contacts: [], tags: [])
    2.times do
      post "/knowledge_items/#{src.uuid}/comment_at",
           params: { anchor: "cnt" },
           headers: { "Accept" => "application/json" }
    end
    get "/knowledge_items/#{src.uuid}/card"
    assert_match(/title="2 Backlinks"/, @response.body)

    # Einen löschen → Counter zeigt 1
    a_uuid = KnowledgeItemReference.where(target_uuid: src.uuid).first.source_uuid
    FileProxy.destroy(actor: @hans, knowledge_item: KnowledgeItem.find_by(uuid: a_uuid))
    get "/knowledge_items/#{src.uuid}/card"
    assert_match(/title="1 Backlink"/, @response.body)
  end

  # #155: Bulk-Trigger für Entity-Import.
  test "POST /knowledge_items/:uuid/request_entity_import legt Task für Researcher an" do
    researcher = AgentActor.create!(name: "miolim Researcher",
                                    email: "miolim_researcher@miolim.de",
                                    description: "Recherche-Agent")
    grant(@hans, "Task", %w[create])

    src = FileProxy.create(actor: @hans, title: "Forschungsnote",
                           item_type: :note,
                           content: "Forschung mit [[Anna Schneider | https://lab.eth.ch/anna]] und [[ETH Zürich | https://ethz.ch]].",
                           topics: [], contacts: [], tags: [])

    assert_difference -> { Task.count }, 1 do
      post "/knowledge_items/#{src.uuid}/request_entity_import",
           headers: { "Accept" => "application/json" }
    end
    assert_response :success
    json = JSON.parse(@response.body)
    assert_equal 2, json["count"]
    task = Task.find(json["task_id"])
    assert_equal researcher.id, task.assignee_id
    assert_includes task.tags, "entity_import"
    assert_includes task.description, "Anna Schneider"
    assert_includes task.description, "https://lab.eth.ch/anna"
    assert_includes task.description, "ETH Zürich"
  end

  test "POST request_entity_import gibt count=0 zurück wenn keine missing Wikilinks mit URL" do
    AgentActor.create!(name: "miolim Researcher",
                       email: "miolim_researcher@miolim.de",
                       description: "Recherche-Agent")
    grant(@hans, "Task", %w[create])

    src = FileProxy.create(actor: @hans, title: "Saubere Note",
                           item_type: :note,
                           content: "Normale [[Wikilink]] ohne URL.",
                           topics: [], contacts: [], tags: [])

    assert_no_difference -> { Task.count } do
      post "/knowledge_items/#{src.uuid}/request_entity_import",
           headers: { "Accept" => "application/json" }
    end
    json = JSON.parse(@response.body)
    assert_equal 0, json["count"]
  end

  test "POST request_entity_import ignoriert bereits existierende KIs" do
    AgentActor.create!(name: "miolim Researcher",
                       email: "miolim_researcher@miolim.de",
                       description: "Recherche-Agent")
    grant(@hans, "Task", %w[create])

    # Anna existiert schon
    FileProxy.create(actor: @hans, title: "Anna Schneider",
                     item_type: :person,
                     content: "",
                     topics: [], contacts: [], tags: [])

    src = FileProxy.create(actor: @hans, title: "Forschungsnote",
                           item_type: :note,
                           content: "Mit [[Anna Schneider | https://lab.eth.ch/anna]] und [[ETH Zürich | https://ethz.ch]].",
                           topics: [], contacts: [], tags: [])

    post "/knowledge_items/#{src.uuid}/request_entity_import",
         headers: { "Accept" => "application/json" }
    json = JSON.parse(@response.body)
    # Nur ETH Zürich ist noch missing — Anna ist schon da.
    assert_equal 1, json["count"]
    task = Task.find(json["task_id"])
    assert_includes     task.description, "ETH Zürich"
    refute_includes     task.description, "Anna Schneider"
  end

  test "POST request_entity_import scheitert ohne Researcher-Agent" do
    grant(@hans, "Task", %w[create])
    src = FileProxy.create(actor: @hans, title: "Test",
                           item_type: :note,
                           content: "[[X | https://x.org]]",
                           topics: [], contacts: [], tags: [])
    post "/knowledge_items/#{src.uuid}/request_entity_import",
         headers: { "Accept" => "application/json" }
    assert_response :unprocessable_entity
    assert_includes @response.body, "Researcher-Agent"
  end

  test "Counter-Icon trägt data-source-uuids für Stack-Highlighting" do
    src = FileProxy.create(actor: @hans, title: "Highlight-Test",
                           item_type: :note,
                           content: "Y ^hl",
                           topics: [], contacts: [], tags: [])
    post "/knowledge_items/#{src.uuid}/comment_at",
         params: { anchor: "hl" },
         headers: { "Accept" => "application/json" }
    comment_uuid = JSON.parse(@response.body)["uuid"]

    get "/knowledge_items/#{src.uuid}/card"
    assert_match(/data-source-uuids="#{comment_uuid}"/, @response.body)
  end

  # ─── #191 pinned / toggle_pin ────────────────────────────────────────

  test "POST /knowledge_items/:uuid/toggle_pin pinnt und liefert JSON {pinned: true, count}" do
    item = FileProxy.create(actor: @hans, title: "Zum Pinnen",
                            item_type: :note, content: "x",
                            topics: [], contacts: [], tags: [])
    assert_difference -> { KnowledgeItemPin.count }, 1 do
      post "/knowledge_items/#{item.uuid}/toggle_pin",
           headers: { "Accept" => "application/json" }
    end
    assert_response :success
    data = JSON.parse(@response.body)
    assert data["pinned"]
    assert_equal 1, data["count"]
    assert_equal item.uuid, data["uuid"]
  end

  test "POST toggle_pin zweimal entfernt den Pin (Toggle)" do
    item = FileProxy.create(actor: @hans, title: "Toggle-Test",
                            item_type: :note, content: "x",
                            topics: [], contacts: [], tags: [])
    post "/knowledge_items/#{item.uuid}/toggle_pin", headers: { "Accept" => "application/json" }
    assert_equal 1, KnowledgeItemPin.where(actor_id: @hans.id).count
    post "/knowledge_items/#{item.uuid}/toggle_pin", headers: { "Accept" => "application/json" }
    data = JSON.parse(@response.body)
    refute data["pinned"]
    assert_equal 0, data["count"]
  end

  test "GET /pinned listet nur gepinnte KIs des aktuellen Actors" do
    pinned_ki   = FileProxy.create(actor: @hans, title: "Gepinnt", item_type: :note, content: "x",
                                    topics: [], contacts: [], tags: [])
    unpinned_ki = FileProxy.create(actor: @hans, title: "Nicht gepinnt", item_type: :note, content: "y",
                                    topics: [], contacts: [], tags: [])
    KnowledgeItemPin.create!(actor: @hans, knowledge_item: pinned_ki)

    get "/pinned"
    assert_response :success
    assert_includes @response.body, "Gepinnt"
    refute_includes @response.body, "Nicht gepinnt"
  end

  # ─── #196 detail_pane ────────────────────────────────────────────────

  # #680 (Hans): Backlink auf eine Antwort öffnet im Person-Backlinks-Panel
  # NICHT die titellose Antwort als eigenes Blade, sondern das Mutter-Item
  # (hier: die Aufgabe) und scrollt zur Antwort (nav_uuid/scroll_to).
  test "Person-Backlinks: Antwort-Quelle öffnet das Mutter-Item + scrollt zur Antwort" do
    grant(@hans, "Task", %w[read create update delete])
    person = FileProxy.create(actor: @hans, title: "Norbert Wiener",
                              item_type: :person, content: "",
                              topics: [], contacts: [], tags: [])
    task = Task.create!(title: "Recherche: Norbert Wiener", creator: @hans, status: :open)
    reply = FileProxy.create(actor: @hans, title: "r", item_type: :reply,
                             content: "Siehe [[Norbert Wiener]].\n",
                             topics: [], contacts: [], tags: [])
    reply.update!(title: nil, parent_type: "Task", parent_id_int: task.id,
                  published_at: Time.current)
    # Eingehende Referenz Antwort -> Person sicherstellen (sonst kein Backlink)
    KnowledgeItemReference.find_or_create_by!(
      source_uuid: reply.uuid, target_uuid: person.uuid,
      target_title: "Norbert Wiener",
      anchor_type: :file, anchor_text: "Norbert Wiener"
    )

    get "/knowledge_items/#{person.uuid}/detail_pane",
        headers: { "Accept" => "text/html, text/vnd.turbo-stream.html",
                   "Turbo-Frame" => "knowledge_detail" }
    assert_response :success
    # Navigationsziel = Aufgabe (task:<id>), Scroll = reply_<uuid>
    assert_includes @response.body, %(data-target-uuid="task:#{task.id}")
    assert_includes @response.body, %(data-target-anchor="reply_#{reply.uuid}")
    assert_includes @response.body, "Recherche: Norbert Wiener: Antwort"
    # NICHT die nackte Antwort-UUID als Ziel
    refute_includes @response.body, %(data-target-uuid="#{reply.uuid}")
  end

  # #681 (Hans): Personen-Blade-Anpassungen — Typ-Auswahl auf Person/Org
  # beschränkt, „persönlich bekannt"-Toggle in der Details-Section, leere
  # Editor-Sektionen eingeklappt.
  test "Personen-Blade: Typ-Auswahl beschränkt, Known-Toggle oben, leere Sektionen eingeklappt" do
    person = FileProxy.create(actor: @hans, title: "Typ-Test-Person",
                              item_type: :person, content: "",
                              topics: [], contacts: [], tags: [])
    get "/knowledge_items/#{person.uuid}/detail_pane",
        headers: { "Accept" => "text/html, text/vnd.turbo-stream.html",
                   "Turbo-Frame" => "knowledge_detail" }
    assert_response :success
    body = @response.body
    # #4: Typ-Select kennt nur person + organization, NICHT note/source
    assert_includes body, %(<option selected="selected" value="person">)
    assert_includes body, %(<option value="organization">)
    refute_includes body, %(value="note">)
    refute_includes body, %(value="source">)
    # #3: Known-Toggle ist im Blade vorhanden
    assert_includes body, "als persönlich bekannt markieren"
    # #1: leere Adress-Sektion ist eingeklappt (content hat hidden)
    assert_match(/postal_addresses_section_#{person.uuid}.*?data-disclosure-target="content" class="[^"]*hidden/m, body)
  end

  # #683 (Hans): PDF-Anhänge bekommen zwei Spine-Aktionen — Full-Blade
  # (pdf-fullblade-Controller) + Öffnen in neuem Tab (Link auf file_url).
  # Nicht-PDF-KIs zeigen sie nicht.
  test "Stack-Card eines PDF-KI hat Full-Blade- und Neuer-Tab-Spine-Aktion" do
    pdf_ki = FileProxy.create(actor: @hans, title: "PDF-Quelle",
                              item_type: :transcript, content: "x",
                              topics: [], contacts: [], tags: [])
    pdf_ki.update_column(:file_path, "knowledge/transcripts/test-#{pdf_ki.uuid}.pdf")
    get card_knowledge_item_path(pdf_ki.uuid)
    assert_response :success
    assert_includes @response.body, %(data-controller="pdf-fullblade")
    assert_includes @response.body, %(data-pdf-fullblade-url-value="#{file_knowledge_item_path(pdf_ki.uuid)}")
    assert_match(/href="#{Regexp.escape(file_knowledge_item_path(pdf_ki.uuid))}"[^>]*target="_blank"/, @response.body)
  end

  test "Stack-Card eines Nicht-PDF-KI hat KEINE PDF-Spine-Aktionen" do
    note = FileProxy.create(actor: @hans, title: "Normale Notiz",
                            item_type: :note, content: "Text",
                            topics: [], contacts: [], tags: [])
    get card_knowledge_item_path(note.uuid)
    assert_response :success
    refute_includes @response.body, %(data-controller="pdf-fullblade")
  end

  test "GET /knowledge_items/:uuid/detail_pane rendert KI in statischem knowledge_detail-Frame" do
    item = FileProxy.create(actor: @hans, title: "Detail-Pane",
                            item_type: :note, content: "x",
                            topics: [], contacts: [], tags: [])
    get "/knowledge_items/#{item.uuid}/detail_pane",
        headers: { "Accept" => "text/html, text/vnd.turbo-stream.html",
                   "Turbo-Frame" => "knowledge_detail" }
    assert_response :success
    # Statischer Frame, kein UUID-Suffix
    assert_match(/turbo-frame[^>]+id="knowledge_detail"/, @response.body)
    assert_includes @response.body, "Detail-Pane"
  end

  # #231: ohne Frame-Header (= Mobile-Klick aus History-Liste) leitet
  # detail_pane auf /knowledge_items?stack=<uuid> um, sonst sieht der
  # User die layoutlose Frame-Antwort.
  test "GET /knowledge_items/:uuid/detail_pane ohne Turbo-Frame leitet auf Stack" do
    item = FileProxy.create(actor: @hans, title: "Detail-Pane-Mobile",
                            item_type: :note, content: "x",
                            topics: [], contacts: [], tags: [])
    get "/knowledge_items/#{item.uuid}/detail_pane"
    assert_redirected_to knowledge_items_path(stack: "list:history,#{item.uuid}")
  end

  # ─── #127 binary-file streaming ─────────────────────────────────────

  test "GET /knowledge_items/:uuid/file streamt Binär-Anhang inline" do
    with_isolated_miolimos_base do |base|
      uploaded = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4 stub"),
                                               "application/pdf", original_filename: "test.pdf")
      item = FileProxy.create_with_file(actor: @hans, title: "Mein PDF",
                                         uploaded_io: uploaded, item_type: :transcript)
      get "/knowledge_items/#{item.uuid}/file"
      assert_response :success
      assert_equal "application/pdf", response.media_type
      assert_includes response.body, "%PDF-1.4 stub"
    end
  end

  # ─── #183 start_wikilink_research ────────────────────────────────────

  test "POST start_wikilink_research legt EINEN Task + Job für genau einen Wikilink an" do
    grant(@hans, "Task", %w[read create update delete])
    AgentActor.create!(name: "miolim Researcher",
                       email: "miolim_researcher@miolim.de",
                       description: "Recherche-Agent", active: true)
    src = FileProxy.create(actor: @hans, title: "Source mit Wikilinks",
                           item_type: :note,
                           content: "[[X | https://example.com/x]]",
                           topics: [], contacts: [], tags: [])
    assert_difference [ -> { WikilinkResearchJob.count }, -> { Task.count } ], 1 do
      post "/knowledge_items/#{src.uuid}/start_wikilink_research",
           params: { title: "X", source_url: "https://example.com/x" },
           headers: { "Accept" => "application/json" }
    end
    data = JSON.parse(@response.body)
    assert_equal "started", data["state"]
    assert data["job_id"].present?
  end

  test "POST start_wikilink_research zweiter Aufruf für gleichen Title ist idempotent" do
    grant(@hans, "Task", %w[read create update delete])
    AgentActor.create!(name: "miolim Researcher",
                       email: "miolim_researcher@miolim.de",
                       description: "Recherche-Agent", active: true)
    src = FileProxy.create(actor: @hans, title: "S", item_type: :note,
                           content: "[[Y | https://e/y]]",
                           topics: [], contacts: [], tags: [])
    post "/knowledge_items/#{src.uuid}/start_wikilink_research",
         params: { title: "Y", source_url: "https://e/y" },
         headers: { "Accept" => "application/json" }
    assert_no_difference -> { WikilinkResearchJob.count } do
      post "/knowledge_items/#{src.uuid}/start_wikilink_research",
           params: { title: "Y", source_url: "https://e/y" },
           headers: { "Accept" => "application/json" }
    end
    data = JSON.parse(@response.body)
    assert_equal "already_running", data["state"]
  end

  # #676 (Hans): Recherche abbrechen = Recherche-Task löschen. Der Job
  # muss mitgelöscht werden, und der ⏳-Indikator (der auf den Task zeigte)
  # verschwindet — kein 404 mehr. Verwaiste Jobs (Task schon weg) fallen
  # im Render auf den 🔍-Start-Indikator zurück.
  test "Recherche-Task löschen entfernt den Job und damit die Sanduhr" do
    grant(@hans, "Task", %w[read create update delete])
    AgentActor.create!(name: "miolim Researcher",
                       email: "miolim_researcher@miolim.de",
                       description: "Recherche-Agent", active: true)
    src = FileProxy.create(actor: @hans, title: "Quelle",
                           item_type: :note,
                           content: "[[Glenn Whale | https://example.com/gw]]",
                           topics: [], contacts: [], tags: [])
    post "/knowledge_items/#{src.uuid}/start_wikilink_research",
         params: { title: "Glenn Whale", source_url: "https://example.com/gw" },
         headers: { "Accept" => "application/json" }
    job = WikilinkResearchJob.find_by!(source_knowledge_item_id: src.uuid,
                                       target_title: "Glenn Whale")
    item = KnowledgeItem.find(src.uuid)

    # solange der Task lebt: ⏳ (pending)
    html = KnowledgeMarkdown.new(item.body, item: item).render
    assert_includes html, "wikilink-research-pending"

    # Task löschen = Recherche abbrechen → Job weg
    assert_difference -> { WikilinkResearchJob.count }, -1 do
      Task.find(job.task_id).destroy!
    end

    # ⏳ ist weg, stattdessen wieder der 🔍-Start-Indikator, kein 404-Link
    html = KnowledgeMarkdown.new(item.body, item: item).render
    refute_includes html, "wikilink-research-pending"
    assert_includes html, "wikilink-research-start"
  end

  test "POST start_wikilink_research ohne title oder source_url ist 422" do
    grant(@hans, "Task", %w[read create update delete])
    AgentActor.create!(name: "miolim Researcher",
                       email: "miolim_researcher@miolim.de",
                       description: "Recherche-Agent", active: true)
    src = FileProxy.create(actor: @hans, title: "S", item_type: :note,
                           content: "x", topics: [], contacts: [], tags: [])
    post "/knowledge_items/#{src.uuid}/start_wikilink_research",
         params: { title: "" },
         headers: { "Accept" => "application/json" }
    assert_response :unprocessable_entity
  end

  # ─── new (Render-Test) ──────────────────────────────────────────────

  test "GET /knowledge_items/new rendert Form" do
    get "/knowledge_items/new"
    assert_response :success
    assert_select "form[action='/knowledge_items']"
  end

  test "GET /knowledge_items/new mit in_stack=1 rendert nur stack_new_card-Partial (kein Layout)" do
    get "/knowledge_items/new", params: { in_stack: 1, type: "note" }
    assert_response :success
    assert_match(/stack_card_new/, @response.body)
    # Kein layout → kein nav.sidebar
    refute_match(%r{<aside[^>]+data-controller="sidebar"}, @response.body)
  end

  # ─── edit (Render-Test) ──────────────────────────────────────────────

  test "GET /knowledge_items/:uuid/edit rendert KI in Edit-Mode" do
    item = FileProxy.create(actor: @hans, title: "Edit-Test",
                            item_type: :note, content: "Original-Inhalt",
                            topics: [], contacts: [], tags: [])
    get "/knowledge_items/#{item.uuid}/edit"
    assert_response :success
    assert_match(/Original-Inhalt/, @response.body)
  end

  # ─── resolve (Bulk-Lookup für History-Drawer) ───────────────────────

  test "POST /knowledge_items/resolve liefert items-Array für gegebene UUIDs" do
    a = FileProxy.create(actor: @hans, title: "Resolve A", item_type: :note, content: "x",
                          topics: [], contacts: [], tags: [])
    b = FileProxy.create(actor: @hans, title: "Resolve B", item_type: :note, content: "y",
                          topics: [], contacts: [], tags: [])
    post "/knowledge_items/resolve",
         params: { uuids: [a.uuid, b.uuid] },
         headers: { "Accept" => "application/json" }
    assert_response :success
    data = JSON.parse(@response.body)
    titles = data["items"].map { |i| i["title"] }.sort
    assert_equal ["Resolve A", "Resolve B"], titles
  end

  test "POST resolve liefert leeres items-Array für nur unbekannte UUIDs" do
    post "/knowledge_items/resolve",
         params: { uuids: [SecureRandom.uuid] },
         headers: { "Accept" => "application/json" }
    assert_response :success
    assert_equal [], JSON.parse(@response.body)["items"]
  end

  # #544 (Hans, 2026-06-08): ID-Nummern (Key-Value, optional mit Gegenseite)
  # direkt in der DB (Source of Truth), ersetzt den ganzen Satz.
  test "PATCH identifiers speichert IDs mit und ohne Gegenseite + löst Gegenseite auf" do
    org = FileProxy.create(actor: @hans, title: "Meine Org", item_type: :organization,
                           content: "", topics: [], contacts: [], tags: [])
    versicherung = FileProxy.create(actor: @hans, title: "Versicherung X", item_type: :organization,
                                    content: "", topics: [], contacts: [], tags: [])

    patch "/knowledge_items/#{org.uuid}/identifiers", params: {
      identifiers: [
        { label: "Versichertennummer", value: "12345", counterparty: "Versicherung X" },
        { label: "Steuernummer",       value: "21/815/00001", counterparty: "" },
        { label: "",                   value: "", counterparty: "" }  # leer -> ignoriert
      ]
    }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :ok

    ids = org.reload.identifiers.ordered.to_a
    assert_equal 2, ids.size
    assert_equal "Versichertennummer", ids[0].label
    assert_equal "12345",              ids[0].value
    assert_equal versicherung.uuid,    ids[0].counterparty_uuid
    assert_equal "Steuernummer",       ids[1].label
    assert_nil   ids[1].counterparty_uuid

    # erneutes PATCH ersetzt den ganzen Satz
    patch "/knowledge_items/#{org.uuid}/identifiers", params: {
      identifiers: [{ label: "Kundennummer", value: "K-9", counterparty: "" }]
    }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    org.reload
    assert_equal 1, org.identifiers.count
    assert_equal "Kundennummer", org.identifiers.first.label
    # beidseitig: bei der Versicherung taucht die Nummer als "für andere" auf -> nach Replace weg
    assert_equal 0, versicherung.reload.identifiers_as_counterparty.count
  end

  # #532 (Hans, 2026-06-08): strukturierte Postadresse DB-direkt (Upsert).
  test "PATCH addresses speichert strukturierte Adresse (Upsert + Replace + leer entfällt)" do
    org = FileProxy.create(actor: @hans, title: "Adress Org", item_type: :organization,
                           content: "", topics: [], contacts: [], tags: [])
    patch "/knowledge_items/#{org.uuid}/addresses", params: {
      addresses: [
        { line1: "Musterstr. 1", postal_code: "20095", city: "Hamburg", country: "DE", billing: "1" },
        { line1: "", postal_code: "", city: "", country: "" }  # leer -> ignoriert
      ]
    }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :ok
    a = org.reload.postal_addresses.ordered.to_a
    assert_equal 1, a.size
    assert_equal "Musterstr. 1", a[0].line1
    assert_equal "Hamburg",      a[0].city
    assert a[0].billing
    assert_equal ["Musterstr. 1", "20095 Hamburg", "DE"], a[0].lines

    keep = a[0].id
    patch "/knowledge_items/#{org.uuid}/addresses", params: {
      addresses: [{ id: keep, line1: "Neue Str. 5", postal_code: "10117", city: "Berlin" }]
    }
    org.reload
    assert_equal 1, org.postal_addresses.count
    assert_equal keep, org.postal_addresses.first.id   # stabile id (Upsert)
    assert_equal "Berlin", org.postal_addresses.first.city
  end

  # #542 (Hans, 2026-06-07): Personen-Eintrag öffnet den dedizierten
  # list:persons-Blade (Personen-Chrome + hartcodierter Person/Org-Filter +
  # Plus zum Anlegen), NICHT den gefilterten Wissens-Blade.
  test "GET /knowledge_items?stack=list:persons rendert Personen-Blade statt Wissens-Blade" do
    get "/knowledge_items", params: { stack: "list:persons" }
    assert_response :success
    assert_includes @response.body, "Personen durchsuchen",
                    "Personen-Suchschlitz fehlt — vermutlich Wissens-Blade gerendert"
    refute_includes @response.body, "Wissen durchsuchen",
                    "Wissens-Blade-Chrome im Personen-Kontext"
    assert_includes @response.body, "stack_card_list:persons",
                    "Personen-Blade-Card nicht im initialen Stack"
  end

  # #705 (Hans): HTML-Render-Modus — Body als sandboxed iframe.
  test "render_mode=html zeigt den Body als sandboxed iframe (isoliert)" do
    item = FileProxy.create(actor: @hans, title: "HTML-Artefakt", item_type: :note,
                            content: "<h1>Hallo HTML</h1>", topics: [], contacts: [], tags: [])
    item.update!(render_mode: "html")
    get "/knowledge_items/#{item.uuid}/card"
    assert_response :success
    assert_includes @response.body, "<iframe"
    assert_includes @response.body, 'sandbox="allow-scripts"'
    refute_includes @response.body, "allow-same-origin"   # kein App-Zugriff
    assert_includes @response.body, "srcdoc="
    refute_includes @response.body, '<article class="markdown-body"'
  end

  test "toggle_render_mode schaltet markdown <-> html" do
    item = FileProxy.create(actor: @hans, title: "Toggle-RM", item_type: :note,
                            content: "x", topics: [], contacts: [], tags: [])
    assert item.reload.render_markdown?
    post "/knowledge_items/#{item.uuid}/toggle_render_mode",
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :ok
    assert item.reload.render_html?
    post "/knowledge_items/#{item.uuid}/toggle_render_mode",
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert item.reload.render_markdown?
  end

  # ContactExtractor.call temporär überschreiben (kein minitest/mock).
  def stub_extractor(result)
    orig = ContactExtractor.method(:call)
    ContactExtractor.define_singleton_method(:call) { |*, **| result }
    yield
  ensure
    ContactExtractor.define_singleton_method(:call, orig)
  end

  # #761 (Hans, 2026-06-23): complete_from_url übernimmt extrahierte
  # Kontaktdaten in die leeren Felder eines Person-KI (ContactExtractor
  # gestubbt — kein echter Fetch/LLM).
  test "complete_from_url ergänzt Kontaktpunkte, Adresse und USt-ID" do
    person = FileProxy.create(actor: @hans, title: "Daniela Test", item_type: :person, content: "")
    extracted = {
      organization: "Test GmbH", email: "info@test.io", phone: "0177 1234567",
      fax: nil, url: "https://test.io", vat_id: "DE123456789",
      register: "Amtsgericht Lübeck HRB 12345",
      address: { line1: "Teststr. 1", line2: nil, postal_code: "12345", city: "Teststadt", country: nil }
    }
    stub_extractor(extracted) do
      post "/knowledge_items/#{person.uuid}/complete_from_url",
           params: { url: "https://test.io/impressum" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    person.reload
    # #761-Folge: USt-IdNr + Handelsregister landen als IDENTIFIER (nicht in
    # der vat_id-Spalte), damit sie im IDs-Bereich der Detailansicht erscheinen.
    ids = person.identifiers.to_h { |i| [i.label, i.value] }
    assert_equal "DE123456789", ids["USt-IdNr"]
    assert_equal "Amtsgericht Lübeck HRB 12345", ids["Handelsregister"]
    assert_includes person.contact_points.map(&:value), "info@test.io"
    assert_includes person.contact_points.map(&:value), "0177 1234567"
    assert_equal 1, person.postal_addresses.count
    assert_equal "Teststr. 1", person.postal_addresses.first.line1
  end

  test "complete_from_url überschreibt vorhandene USt-IdNr NICHT" do
    person = FileProxy.create(actor: @hans, title: "Schon-USt", item_type: :person, content: "")
    person.identifiers.create!(label: "USt-IdNr", value: "DE000000000", position: 0)
    stub_extractor({ vat_id: "DE999999999", email: "neu@x.io" }) do
      post "/knowledge_items/#{person.uuid}/complete_from_url",
           params: { url: "https://x.io" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_equal ["DE000000000"], person.reload.identifiers.where(label: "USt-IdNr").pluck(:value)
    assert_includes person.contact_points.map(&:value), "neu@x.io"
  end

  test "complete_from_url leitet die Webseite aus der Quell-URL ab, wenn das Impressum sie nicht nennt" do
    org = FileProxy.create(actor: @hans, title: "Domain GmbH", item_type: :organization, content: "")
    stub_extractor({ organization: "Domain GmbH", url: nil, email: "x@domain.de" }) do
      post "/knowledge_items/#{org.uuid}/complete_from_url",
           params: { url: "https://www.domain.de/impressum/" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_includes org.reload.contact_points.where(kind: "url").pluck(:value), "https://www.domain.de"
  end

  # #761 (Hans, 2026-06-23): optionale URL im Person-Quick-Add — ist sie
  # gesetzt, zieht der Create-Pfad gleich die Kontaktdaten aus der Quelle.
  test "Person-Quick-Add mit enrich_url füllt Kontaktdaten beim Anlegen" do
    stub_extractor({ organization: "Quick GmbH", email: "hallo@quick.io",
                     phone: "0177 7654321", vat_id: "DE321321321" }) do
      assert_difference -> { KnowledgeItem.where(item_type: :person).count }, 1 do
        post "/knowledge_items",
             params: { quick_create: "1", item_type: "person", title: "Quick Kontakt",
                       enrich_url: "https://quick.io/impressum" },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
    end
    assert_response :success
    person = KnowledgeItem.find_by!(title: "Quick Kontakt")
    assert_includes person.contact_points.map(&:value), "hallo@quick.io"
    assert_includes person.contact_points.map(&:value), "0177 7654321"
    assert_equal "DE321321321", person.identifiers.find_by(label: "USt-IdNr")&.value
  end

  test "Person-Quick-Add ohne enrich_url ruft den Extractor nicht auf" do
    called = false
    orig = ContactExtractor.method(:call)
    ContactExtractor.define_singleton_method(:call) { |*, **| called = true; {} }
    begin
      post "/knowledge_items",
           params: { quick_create: "1", item_type: "person", title: "Ohne URL" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    ensure
      ContactExtractor.define_singleton_method(:call, orig)
    end
    assert_response :success
    refute called, "Extractor darf ohne enrich_url nicht laufen"
  end

  # #786: Bankverbindungen am Person-KI — Upsert (anlegen/ändern/löschen) +
  # IBAN/BIC-Normalisierung.
  test "bank_accounts: anlegen, normalisieren, ersetzen" do
    person = FileProxy.create(actor: @hans, title: "Konto-Person", item_type: :person, content: "")
    patch "/knowledge_items/#{person.uuid}/bank_accounts",
          params: { bank_accounts: [{ iban: "de89 3704 0044 0532 0130 00", bic: "cobadeffxxx",
                                      bank_name: "Commerzbank", holder: "Konto-Person", label: "Privat" }] },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    acc = person.reload.bank_accounts.ordered
    assert_equal 1, acc.size
    assert_equal "DE89370400440532013000", acc.first.iban, "IBAN normalisiert (ohne Spaces, groß)"
    assert_equal "COBADEFFXXX", acc.first.bic
    assert_equal "Privat", acc.first.label

    # nur leere Felder → alle löschen (wie das Formular beim Leeren sendet)
    patch "/knowledge_items/#{person.uuid}/bank_accounts",
          params: { bank_accounts: [{ iban: "", bic: "", bank_name: "", holder: "", label: "" }] },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_equal 0, person.reload.bank_accounts.count
  end

  test "GET KI-Detail einer Person zeigt den Bankverbindungs-Editor (#786)" do
    person = FileProxy.create(actor: @hans, title: "Editor-Person", item_type: :person, content: "")
    get "/knowledge_items/#{person.uuid}/card"
    assert_response :success
    assert_includes @response.body, "bank_accounts_section_#{person.uuid}"
  end
end
