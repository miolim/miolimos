require "test_helper"

# #163 Phase 5a-1: BladeStackLoader parst den ?stack=-Param und liefert
# typisierte Items, die das Stack-View direkt rendern kann.
class BladeStackLoaderTest < ActiveSupport::TestCase
  setup do
    @hans  = create_human
    # #602 S1: der Loader scoped über Current.actor (im Web-Request vom
    # ApplicationController gesetzt) — Service-Test setzt ihn explizit.
    Current.actor = @hans
    @ki    = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "K", item_type: "note",
                                   creator: @hans, file_path: "k.md", content_hash: "h")
    @task  = Task.create!(title: "T", creator: @hans)
    @topic = Topic.create!(name: "Topo", slug: "topo-#{SecureRandom.hex(2)}", creator: @hans)
    @src   = Source.create!(title: "S", slug: "src-#{SecureRandom.hex(2)}",
                            csl_type: "book", creator: @hans)
  end

  test "leerer Param liefert leere Liste" do
    assert_equal [], BladeStackLoader.parse(nil)
    assert_equal [], BladeStackLoader.parse("")
    assert_equal [], BladeStackLoader.parse("  ")
  end

  test "plain UUID wird als KI-Item geladen" do
    items = BladeStackLoader.parse(@ki.uuid)
    assert_equal 1, items.size
    assert_equal :ki, items.first.kind
    assert_equal @ki, items.first.record
  end

  test "task: prefix wird als Task-Item geladen" do
    items = BladeStackLoader.parse("task:#{@task.id}")
    assert_equal :task, items.first.kind
    assert_equal @task, items.first.record
    assert_equal "task:#{@task.id}", items.first.stack_uuid
  end

  test "topic: prefix wird als Topic-Item geladen" do
    items = BladeStackLoader.parse("topic:#{@topic.slug}")
    assert_equal :topic, items.first.kind
    assert_equal @topic, items.first.record
  end

  test "list:topic:<slug> wird als Topic-List-Item geladen mit korrekter stack_uuid" do
    items = BladeStackLoader.parse("list:topic:#{@topic.slug}")
    assert_equal :topic_list, items.first.kind
    assert_equal @topic, items.first.record
    assert_equal "list:topic:#{@topic.slug}", items.first.stack_uuid
    assert_equal "topics/index_list_blade", items.first.partial
  end

  test "src: prefix wird als Source-Item geladen" do
    items = BladeStackLoader.parse("src:#{@src.slug}")
    assert_equal :source, items.first.kind
    assert_equal @src, items.first.record
    assert_equal "src:#{@src.slug}", items.first.stack_uuid
  end

  test "gemischter Stack behaelt Reihenfolge" do
    param = "#{@ki.uuid},task:#{@task.id},topic:#{@topic.slug},src:#{@src.slug}"
    items = BladeStackLoader.parse(param)
    assert_equal [:ki, :task, :topic, :source], items.map(&:kind)
  end

  test "unbekannte IDs werden ausgelassen" do
    param = "#{@ki.uuid},task:99999,topic:does-not-exist,src:nope-nope"
    items = BladeStackLoader.parse(param)
    assert_equal [:ki], items.map(&:kind)
  end

  test "unbekannter Prefix wird ausgelassen" do
    items = BladeStackLoader.parse("foo:bar,#{@ki.uuid}")
    assert_equal [:ki], items.map(&:kind)
  end

  test "Item.partial liefert das richtige Partial pro Typ" do
    assert_equal "knowledge_items/stack_card", BladeStackLoader::Item.new(kind: :ki,     id: "x", record: @ki).partial
    assert_equal "tasks/blade_card",           BladeStackLoader::Item.new(kind: :task,   id: "1", record: @task).partial
    assert_equal "topics/index_list_blade",    BladeStackLoader::Item.new(kind: :topic,  id: "s", record: @topic).partial
    assert_equal "sources/stack_card",         BladeStackLoader::Item.new(kind: :source, id: "s", record: @src).partial
  end

  test "list: prefix mit bekanntem Typ wird zum Listen-Item" do
    items = BladeStackLoader.parse("list:tasks")
    assert_equal :list, items.first.kind
    assert_equal "tasks", items.first.id
    assert_nil items.first.record
    assert_equal "list:tasks", items.first.stack_uuid
    # #275: tasks/index_list_blade ist die rich Variante (vorher
    # tasks/list_blade_card — wurde umbenannt).
    assert_equal "tasks/index_list_blade", items.first.partial
  end

  test "list: prefix mit unbekanntem Typ wird ausgelassen" do
    items = BladeStackLoader.parse("list:does-not-exist,#{@ki.uuid}")
    assert_equal [:ki], items.map(&:kind)
  end

  test "alle bekannten list-Typen werden erkannt" do
    %w[tasks awaitings communications sources inbox_items pinned history].each do |lt|
      items = BladeStackLoader.parse("list:#{lt}")
      assert_equal 1, items.size, "list:#{lt} muss erkannt werden"
      assert_equal :list, items.first.kind
      assert_equal lt, items.first.id
      assert items.first.partial.present?, "Partial-Mapping fuer #{lt}"
    end
  end

  test "awaiting: + communication: prefixes werden als Detail-Items erkannt" do
    awaiting      = Awaiting.create!(title: "Probe-Wartepunkt", creator: @hans, follow_up_at: Date.tomorrow)
    communication = Communication.create!(direction: "inbound", subject: "Probe-Mail",
                                          external_id: "probe-#{SecureRandom.hex(4)}")
    param = "awaiting:#{awaiting.id},communication:#{communication.id}"
    items = BladeStackLoader.parse(param)
    assert_equal [:awaiting, :communication], items.map(&:kind)
    assert_equal awaiting,      items.first.record
    assert_equal communication, items.last.record
    assert_equal "awaiting:#{awaiting.id}",            items.first.stack_uuid
    assert_equal "communication:#{communication.id}",  items.last.stack_uuid
    assert_equal "awaitings/blade_card",      items.first.partial
    assert_equal "communications/blade_card", items.last.partial
  end
end
