require "test_helper"

# #630: Copy-Referenz-Button im Blade-Spine — Wikilink wo es Syntax
# gibt (KI/Task/Quelle), sonst URL.
class BladeCopyButtonTest < ActionDispatch::IntegrationTest
  setup do
    @hans = create_human(password: "secretsecret")
    %w[KnowledgeItem Task Topic Source InboxItem Communication Actor].each do |rt|
      grant(@hans, rt, %w[read create update delete])
    end
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "Task-Blade kopiert [[#id]]" do
    task = Task.create!(title: "Copy-Task", creator: @hans)
    get "/tasks", params: { stack: "list:tasks,task:#{task.id}" }
    assert_response :success
    assert_includes @response.body, %(data-copy-clipboard-content-value="[[##{task.id}]]")
  end

  test "KI-Blade kopiert [[Titel]]; Titel mit Syntax-Brechern fällt auf [[uuid]] zurück" do
    item = create_ki(title: "Copy-KI-Eintrag")
    get "/knowledge_items", params: { stack: item.uuid }
    assert_response :success
    assert_includes @response.body, %(data-copy-clipboard-content-value="[[Copy-KI-Eintrag]]")

    weird = create_ki(title: "Hat [Klammer] drin")
    get "/knowledge_items", params: { stack: weird.uuid }
    assert_includes @response.body, %(data-copy-clipboard-content-value="[[#{weird.uuid}]]")
  end

  test "Topic-Blade kopiert die Topic-URL" do
    topic = Topic.create!(name: "Copy-Thema", slug: "copy-#{SecureRandom.hex(3)}", creator: @hans)
    get "/topics/#{topic.slug}"
    assert_response :success
    assert_includes @response.body, %(data-copy-clipboard-content-value="http://www.example.com/topics/#{topic.slug}")
  end

  test "Inbox-Detail-Blade kopiert die Inbox-URL" do
    item = InboxItem.create!(source_kind: "text", raw_content: "x", status: "pending", creator: @hans)
    get "/inbox", params: { stack: "list:inbox_items,inboxitem:#{item.id}" }
    assert_response :success
    assert_includes @response.body, %(data-copy-clipboard-content-value="http://www.example.com/inbox/#{item.id}")
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
