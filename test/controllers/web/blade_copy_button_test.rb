require "test_helper"

# #630: Copy-Referenz-Button im Blade-Spine.
# #1617 (Hans): „Es wird grundsätzlich immer der Link kopiert. Mit
# UMSCHALT+Mausklick wird der Wikilink kopiert, falls vorhanden." — der
# Button trägt immer den Link und, wo es Syntax gibt (KI/Task/Quelle),
# zusätzlich den Wikilink.
class BladeCopyButtonTest < ActionDispatch::IntegrationTest
  setup do
    @hans = create_human(password: "secretsecret")
    %w[KnowledgeItem Task Topic Source InboxItem Communication Actor].each do |rt|
      grant(@hans, rt, %w[read create update delete])
    end
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "Task-Blade: Link auf die Aufgabe, Umschalt-Wikilink [[#id]]" do
    task = Task.create!(title: "Copy-Task", creator: @hans)
    get "/tasks", params: { stack: "list:tasks,task:#{task.id}" }
    assert_response :success
    assert_includes @response.body, %(data-copy-clipboard-content-value="http://www.example.com/tasks?stack=task:#{task.id}")
    assert_includes @response.body, %(data-copy-clipboard-wikilink-value="[[##{task.id}]]")
    assert_includes @response.body, %(title="Link kopieren · Umschalt+Klick: Wikilink kopieren")
  end

  test "KI-Blade: Link auf die KI, Umschalt-Wikilink [[Titel]]; Syntax-Brecher fallen auf [[uuid]] zurück" do
    item = create_ki(title: "Copy-KI-Eintrag")
    get "/knowledge_items", params: { stack: item.uuid }
    assert_response :success
    assert_includes @response.body, %(data-copy-clipboard-content-value="http://www.example.com/knowledge_items?stack=#{item.uuid}")
    assert_includes @response.body, %(data-copy-clipboard-wikilink-value="[[Copy-KI-Eintrag]]")

    weird = create_ki(title: "Hat [Klammer] drin")
    get "/knowledge_items", params: { stack: weird.uuid }
    assert_includes @response.body, %(data-copy-clipboard-wikilink-value="[[#{weird.uuid}]]")
  end

  test "Topic-Blade: nur der Link, kein Wikilink" do
    topic = Topic.create!(name: "Copy-Thema", slug: "copy-#{SecureRandom.hex(3)}", creator: @hans)
    get "/topics/#{topic.slug}"
    assert_response :success
    assert_includes @response.body, %(data-copy-clipboard-content-value="http://www.example.com/topics/#{topic.slug}")
    assert_not_includes @response.body, "data-copy-clipboard-wikilink-value"
    assert_includes @response.body, %(title="Link kopieren")
  end

  test "Inbox-Detail-Blade: nur der Link" do
    item = InboxItem.create!(source_kind: "text", raw_content: "x", status: "pending", creator: @hans)
    get "/inbox", params: { stack: "list:inbox_items,inboxitem:#{item.id}" }
    assert_response :success
    assert_includes @response.body, %(data-copy-clipboard-content-value="http://www.example.com/inbox/#{item.id}")
    assert_not_includes @response.body, "data-copy-clipboard-wikilink-value"
  end

  # #636: Topic-Farbpunkt im Spine des Items.
  test "Task-Spine zeigt Topic-Farbpunkt mit Klick-zum-Thema" do
    topic = Topic.create!(name: "Punkt-Thema", slug: "punkt-#{SecureRandom.hex(3)}",
                          color: "#ff0000", creator: @hans)
    task = Task.create!(title: "Punkt-Task", creator: @hans)
    task.topics << topic

    get "/tasks", params: { stack: "list:tasks,task:#{task.id}" }
    assert_response :success
    assert_includes @response.body, %(title="Thema: Punkt-Thema")
    assert_includes @response.body, %(data-blade-link-id-value="#{topic.slug}")
    assert_includes @response.body, "background: #ff0000"
  end

  private

  def create_ki(title:)
    KnowledgeItem.create!(uuid: SecureRandom.uuid, title: title, item_type: :note,
                          file_path: "x/#{SecureRandom.hex(4)}.md", content_hash: "h",
                          body: "Inhalt #{SecureRandom.hex(2)}")
  end
end
