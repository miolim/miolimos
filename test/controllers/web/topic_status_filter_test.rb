require "test_helper"

# #817: Topic-Status reduziert auf aktiv/inaktiv; Themen-Liste bekommt
# einen Inaktiv-Filter, der Tipp-Picker markiert inaktive Themen.
class TopicStatusFilterTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-ts-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Topic", %w[read create update])
    post "/login", params: { email: @hans.email, password: "secretsecret" }

    @aktiv   = create_topic(creator: @hans, name: "Aktives Thema")
    @inaktiv = Topic.create!(name: "Ruhendes Thema", slug: "ruhend-#{SecureRandom.hex(2)}",
                             creator: @hans, status: :inactive)
  end

  test "list blade shows only active topics by default" do
    get "/topics/list_card"
    assert_response :ok
    assert_includes @response.body, "Aktives Thema"
    assert_not_includes @response.body, "Ruhendes Thema"
    assert_includes @response.body, "topics_list_frame"
  end

  test "list blade with show_inactive includes marked inactive topics" do
    get "/topics/list_card?show_inactive=1"
    assert_response :ok
    assert_includes @response.body, "Ruhendes Thema"
    assert_includes @response.body, "inaktiv"
  end

  test "suggest marks inactive topics but still finds them" do
    get "/topics/suggest?q=Thema", headers: { "Accept" => "application/json" }
    assert_response :ok
    items = JSON.parse(@response.body)["items"]
    labels = items.map { |i| i["label"] }
    assert_includes labels, "Aktives Thema"
    inactive_item = items.find { |i| i["slug"] == @inaktiv.slug }
    assert inactive_item, "inactive topic must remain findable"
    assert inactive_item["inactive"]
    assert_match(/inaktiv/, inactive_item["label"])
  end

  test "old statuses are gone from the enum" do
    assert_equal %w[active inactive], Topic.statuses.keys
  end
end
