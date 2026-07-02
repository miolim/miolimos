require "test_helper"

# #801 P1: Tests für POST /stack/resolve (#434 Teil 2) + StackHistoryResolver —
# Verlauf-Drawer-Label-Auflösung, vorher 0 % gedeckt.
class StackControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-sk-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Task", %w[read])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "POST /stack/resolve resolves mixed ids to labeled items with icons" do
    task = Task.create!(title: "Stack-Task", creator: @hans)

    post "/stack/resolve",
         params: { ids: ["task:#{task.id}", "list:tasks", "task:999999"] },
         headers: { "Accept" => "application/json" }
    assert_response :ok

    items = JSON.parse(@response.body)["items"]
    assert_equal 3, items.size

    by_uuid = items.index_by { |i| i["uuid"] }
    assert_equal "Stack-Task", by_uuid["task:#{task.id}"]["title"]
    assert_equal "task",       by_uuid["task:#{task.id}"]["item_type"]
    assert_equal "Aufgaben",   by_uuid["list:tasks"]["title"]
    # gelöschte/unbekannte Einträge kommen als missing zurück, nicht als Fehler
    assert_equal "missing",    by_uuid["task:999999"]["item_type"]
    assert items.all? { |i| i["icon_svg"].to_s.include?("<svg") }, "every item gets a server-rendered icon"
  end

  test "POST /stack/resolve with empty ids returns empty list" do
    post "/stack/resolve", params: { ids: [] },
         headers: { "Accept" => "application/json" }
    assert_response :ok
    assert_equal [], JSON.parse(@response.body)["items"]
  end
end

# Service-Fälle, die über den Controller schwer zu treffen sind.
class StackHistoryResolverTest < ActiveSupport::TestCase
  test "resolve maps list ids to German labels and unknown lists to humanized id" do
    labels = StackHistoryResolver.resolve(["list:dashboard"]).first
    assert_equal "Dashboard", labels[:title]
    assert_equal "list", labels[:item_type]
  end

  test "resolve labels tag lists with tag prefix" do
    item = StackHistoryResolver.resolve(["list:tag:steuer"]).first
    assert_equal "Tag: steuer", item[:title]
    assert_equal "tag_list", item[:item_type]
  end

  test "resolve returns [] for blank input" do
    assert_equal [], StackHistoryResolver.resolve(nil)
    assert_equal [], StackHistoryResolver.resolve(["", nil])
  end
end
