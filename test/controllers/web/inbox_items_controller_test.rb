require "test_helper"

class InboxItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-ibx-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "InboxItem", %w[read create update delete])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "GET index lists pending items by default and exposes counts" do
    pending = InboxItem.create!(creator: @hans, source_kind: "text",
                                raw_content: "neu", status: "pending", title: "Pending one")
    # #618 v3: verarbeitet-und-archiviert gehört in den Importe-Reiter,
    # also raus aus der Default-Ansicht (WIP).
    archived = InboxItem.create!(creator: @hans, source_kind: "text",
                                 raw_content: "alt", status: "archived",
                                 processed_at: Time.current, title: "Archived one")

    get "/inbox"
    assert_response :ok
    assert_includes @response.body, pending.title
    refute_includes @response.body, archived.title
  end

  test "GET index with explicit status filters" do
    InboxItem.create!(creator: @hans, source_kind: "text", raw_content: "x",
                      status: "pending", title: "P")
    archived = InboxItem.create!(creator: @hans, source_kind: "text",
                                 raw_content: "y", status: "archived",
                                 processed_at: Time.current, title: "A-archived-uniq")

    get "/inbox", params: { status: "archived" }
    assert_response :ok
    assert_includes @response.body, archived.title
  end

  test "POST create with source_url infers source_kind=web_url" do
    assert_difference -> { InboxItem.count }, 1 do
      post "/inbox", params: { source_url: "https://example.com/foo" }
    end
    item = InboxItem.last
    assert_equal "web_url", item.source_kind
    assert_equal @hans.id, item.creator_id
    assert_includes @response.redirect_url, "inboxitem%3A#{item.id}"  # #618: Stack-URL
  end

  test "POST create infers source_kind=youtube_url" do
    post "/inbox", params: { source_url: "https://youtu.be/abc12345xyz" }
    assert_equal "youtube_url", InboxItem.last.source_kind
  end

  test "POST create with raw_content only infers source_kind=markdown" do
    post "/inbox", params: { raw_content: "# Hi" }
    assert_equal "markdown", InboxItem.last.source_kind
  end

  test "PATCH update changes title" do
    item = InboxItem.create!(creator: @hans, source_kind: "text",
                             raw_content: "x", status: "pending", title: "alt")
    patch "/inbox/#{item.id}", params: { inbox_item: { title: "neu" } }
    assert_includes @response.redirect_url, "inboxitem%3A#{item.id}"  # #618: Stack-URL
    assert_equal "neu", item.reload.title
  end

  test "DELETE destroys item" do
    item = InboxItem.create!(creator: @hans, source_kind: "text",
                             raw_content: "x", status: "pending", title: "weg")
    assert_difference -> { InboxItem.count }, -1 do
      delete "/inbox/#{item.id}"
    end
    assert_redirected_to "/inbox"
  end

  test "POST archive sets status=archived" do
    item = InboxItem.create!(creator: @hans, source_kind: "text",
                             raw_content: "x", status: "pending", title: "arch")
    post "/inbox/#{item.id}/archive"
    assert_redirected_to "/inbox"
    assert_equal "archived", item.reload.status
  end

  test "GET poll on processing item returns 204" do
    item = InboxItem.create!(creator: @hans, source_kind: "text",
                             raw_content: "x", status: "processing", title: "p")
    get "/inbox/#{item.id}/poll"
    assert_response :no_content
  end

  test "GET poll on completed item renders turbo-stream detail update" do
    item = InboxItem.create!(creator: @hans, source_kind: "text",
                             raw_content: "x", status: "processed", title: "done")
    get "/inbox/#{item.id}/poll", headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :ok
  end

  test "POST process_now schedules job and flips status to processing" do
    item = InboxItem.create!(creator: @hans, source_kind: "web_url",
                             source_url: "https://example.com/foo",
                             status: "pending", title: "u")

    assert_enqueued_jobs 1, only: ProcessInboxItemJob do
      post "/inbox/#{item.id}/process",
           params: { processor_kind: "web_clip" }
    end
    assert_includes @response.redirect_url, "inboxitem%3A#{item.id}"  # #618: Stack-URL
    assert_equal "processing", item.reload.status
    assert_equal "web_clip",   item.processor_kind
  end

  test "without InboxItem.delete capability, DELETE is forbidden" do
    no_delete = HumanActor.create!(
      name: "Eve", email: "eve-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(no_delete, "InboxItem", %w[read create update])
    post "/login", params: { email: no_delete.email, password: "secretsecret" }

    item = InboxItem.create!(creator: @hans, source_kind: "text",
                             raw_content: "x", status: "pending", title: "z")
    delete "/inbox/#{item.id}"
    assert_response :forbidden
  end
  # #618: /inbox als Blade-Stack.
  test "GET /inbox rendert das Inbox-Listen-Blade (#618)" do
    get "/inbox"
    assert_response :success
    assert_includes @response.body, %q(data-uuid="list:inbox_items")
  end

  test "card-Endpoint + Stack-Restore liefern das Detail-Blade (#618)" do
    item = InboxItem.create!(source_kind: "web_url", source_url: "https://example.com/x",
                             status: "pending", creator: @hans)
    get "/inbox/#{item.id}/card"
    assert_response :success
    assert_includes @response.body, %Q(data-uuid="inboxitem:#{item.id}")

    get "/inbox", params: { stack: "list:inbox_items,inboxitem:#{item.id}" }
    assert_response :success
    assert_includes @response.body, %Q(data-uuid="inboxitem:#{item.id}")
  end

  test "legacy /inbox/:id leitet auf den Stack (#618)" do
    item = InboxItem.create!(source_kind: "web_url", source_url: "https://example.com/y",
                             status: "pending", creator: @hans)
    get "/inbox/#{item.id}"
    assert_response :redirect
    assert_includes @response.redirect_url, "inboxitem%3A#{item.id}"
  end

  test "list_card filtert per Reiter + inklusiver Statusauswahl (#618 v3)" do
    InboxItem.create!(source_kind: "web_url", source_url: "https://example.com/a",
                      status: "archived", processed_at: Time.current,
                      creator: @hans, title: "Import-Archiv-Eintrag")
    InboxItem.create!(source_kind: "web_url", source_url: "https://example.com/b",
                      status: "archived", creator: @hans, title: "Abgebrochener Eintrag")
    InboxItem.create!(source_kind: "web_url", source_url: "https://example.com/c",
                      status: "failed", creator: @hans, title: "Fehler-Eintrag")

    # Importe-Reiter: verarbeitet-archiviert + Fehler, NICHT das WIP-Archiv.
    get "/inbox/list_card", params: { tab: "importe" }
    assert_response :success
    assert_includes @response.body, "Import-Archiv-Eintrag"
    assert_includes @response.body, "Fehler-Eintrag"
    refute_includes @response.body, "Abgebrochener Eintrag"

    # Inklusive ODER: nur „Fehler" ausgewählt.
    get "/inbox/list_card", params: { tab: "importe", st: ["failed"] }
    assert_includes @response.body, "Fehler-Eintrag"
    refute_includes @response.body, "Import-Archiv-Eintrag"

    # WIP-Reiter enthält das abgebrochene (unverarbeitet archivierte) Item.
    get "/inbox/list_card", params: { tab: "wip" }
    assert_includes @response.body, "Abgebrochener Eintrag"
    refute_includes @response.body, "Import-Archiv-Eintrag"

    # Legacy-Param ?status=archived mappt auf Importe/Archiviert.
    get "/inbox/list_card", params: { status: "archived" }
    assert_includes @response.body, "Import-Archiv-Eintrag"
    refute_includes @response.body, "Fehler-Eintrag"
  end

  # #618 v4: Live-Zeilenupdate + YouTube-Thumbnail.
  # #670: Dublettenkontrolle — Detail warnt + „Als Dublette archivieren".
  test "Detail zeigt Dubletten-Warnung; Archivieren merkt duplicate_of" do
    src = Source.create!(slug: "yt-dupvid123", title: "Video", csl_type: "motion_picture", creator: @hans)
    dupe = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Schon importiert",
                                 item_type: :transcript, file_path: "x/d.md", content_hash: "h",
                                 body: "", bib_source_id: src.id)
    item = InboxItem.create!(creator: @hans, source_kind: "youtube_url",
                             source_url: "https://www.youtube.com/watch?v=dupvid123", status: "pending")

    get "/inbox/#{item.id}/card"
    assert_response :success
    assert_includes @response.body, "Mögliche Dublette"
    assert_includes @response.body, "Schon importiert"

    post "/inbox/#{item.id}/archive", params: { duplicate_of: dupe.uuid }
    item.reload
    assert_equal "archived", item.status
    assert_equal dupe.uuid, item.payload["duplicate_of"]

    get "/inbox/#{item.id}/card"
    assert_includes @response.body, "Als Dublette archiviert"
  end

  test "listen-blade abonniert den User-Stream; Detail zeigt YouTube-Thumbnail" do
    item = InboxItem.create!(source_kind: "youtube_url",
                             source_url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
                             status: "pending", creator: @hans)
    get "/inbox", params: { stack: "list:inbox_items,inboxitem:#{item.id}" }
    assert_response :success
    # Stream-Name steht signiert im Tag.
    assert_includes @response.body,
                    Turbo::StreamsChannel.signed_stream_name("inbox_items_user_#{@hans.id}")
    assert_includes @response.body, "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"
  end

  test "listen-blade-kopf: Titelzeile + Quick-Add-Popover + Reiter (#618 v3)" do
    get "/inbox/list_card"
    assert_response :success
    assert_includes @response.body, "Zur Inbox hinzufügen"      # Popover
    assert_includes @response.body, "Folder scannen"
    assert_includes @response.body, "WIP"
    assert_includes @response.body, "Importe"
  end

  test "alias inbox_items/list_card liefert die Listen-Card (#618 v2)" do
    get "/inbox_items/list_card"
    assert_response :success
    assert_includes @response.body, %q(data-uuid="list:inbox_items")
  end

  # #627: Inbox-Import aus der Topic-Toolbar — Vorgang hängt am Topic.
  test "topic-toolbar bietet Inbox-Import mit Topic-Vorbelegung (#627)" do
    grant(@hans, "Topic", %w[read create update])   # Topic-Blade-Gate
    topic = Topic.create!(name: "Import-Thema", slug: "import-#{SecureRandom.hex(3)}", creator: @hans)
    get "/topics/#{topic.slug}/list_card"
    assert_response :success
    assert_includes @response.body, "data-topic-inbox-import"
    assert_includes @response.body, %Q(value="#{topic.slug}")
    refute_includes @response.body, %Q(<span class="text-xs font-mono text-slate-500 mr-1">#{topic.slug}</span>)

    post "/inbox", params: { source_url: "https://example.com/topic-import", topic_ids: [topic.slug] }
    item = InboxItem.order(:id).last
    assert_equal [topic.id], item.topics.pluck(:id)
  end

  # #627 v2: Import aus dem Topic-Blade hängt das frische Item als
  # Detail-Blade an den AKTUELLEN Stack (Referer trägt den Stack).
  test "create mit stay_in_stack leitet auf den Referer-Stack + Detail-Blade" do
    grant(@hans, "Topic", %w[read create update])
    topic = Topic.create!(name: "Stay-Thema", slug: "stay-#{SecureRandom.hex(3)}", creator: @hans)

    post "/inbox",
         params: { source_url: "https://example.com/stay", topic_ids: [topic.slug], stay_in_stack: "1" },
         headers: { "Referer" => "http://www.example.com/topics?stack=list:topics,topic:#{topic.slug}" }
    item = InboxItem.order(:id).last
    assert_response :redirect
    assert_includes @response.redirect_url, "/topics?stack="
    assert_includes @response.redirect_url, "inboxitem%3A#{item.id}"

    # Die Ziel-Seite rendert den Stack inklusive Inbox-Detail-Blade.
    get @response.redirect_url
    assert_response :success
    assert_includes @response.body, %Q(data-uuid="inboxitem:#{item.id}")

    # Ohne Stack im Referer: Standard-Redirect zur Inbox-Seite.
    post "/inbox",
         params: { source_url: "https://example.com/stay2", stay_in_stack: "1" },
         headers: { "Referer" => "http://www.example.com/dashboard" }
    assert_includes @response.redirect_url, "/inbox?stack="
  end

end
