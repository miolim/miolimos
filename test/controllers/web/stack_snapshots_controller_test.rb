require "test_helper"

# #816: geräteübergreifender Stack-Verlauf — API strikt auf den eigenen
# Actor gescoped; Dedup/Trim-Semantik wie clientseitig.
class StackSnapshotsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-ss-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Actor", %w[read update])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
    @key = "knowledge.stack.history"
  end

  def create_snap(trail: [["u1"], ["u1", "u2"]], current: 1)
    post "/stack_snapshots", params: { key: @key, trail: trail, current: current },
         headers: { "Accept" => "application/json" }, as: :json
    JSON.parse(@response.body)
  end

  test "create stores a snapshot and returns client shape" do
    json = create_snap
    assert_response :created
    assert_equal [["u1"], %w[u1 u2]], json["trail"]
    assert_equal 1, json["current"]
    assert_equal "u1,u2", json["dedupKey"]
    assert json["id"]
  end

  test "create upserts by final composition, newest wins, pin survives" do
    first = create_snap
    StackSnapshot.find(first["id"]).update!(pinned: true)
    second = create_snap(trail: [["start"], ["u1", "u2"]], current: 0)
    assert_equal first["id"], second["id"], "gleiche End-Komposition = derselbe Eintrag"
    snap = StackSnapshot.find(first["id"])
    assert snap.pinned, "Pin muss den Upsert überleben"
    assert_equal [["start"], %w[u1 u2]], snap.trail
  end

  test "non-pinned entries are trimmed to MAX_RECENT per bucket" do
    (StackSnapshot::MAX_RECENT + 3).times { |i| create_snap(trail: [["u#{i}"]], current: 0) }
    assert_equal StackSnapshot::MAX_RECENT,
                 StackSnapshot.for_bucket(@hans, @key).where(pinned: false).count
  end

  test "index returns only own entries for the requested bucket" do
    create_snap
    create_snap(trail: [["anders"]], current: 0)
    post "/stack_snapshots", params: { key: "dashboard.stack.history", trail: [["dash"]], current: 0 }, as: :json

    eve = create_human(password: "secretsecret")
    grant(eve, "Actor", %w[read update])
    StackSnapshot.record!(actor: eve, history_key: @key, trail: [["fremd"]], current: 0)

    get "/stack_snapshots", params: { key: @key }, headers: { "Accept" => "application/json" }
    assert_response :ok
    entries = JSON.parse(@response.body)["entries"]
    assert_equal 2, entries.size
    assert_not entries.any? { |e| e["dedupKey"] == "fremd" }, "fremde Snapshots dürfen nie auftauchen"
  end

  test "update toggles pin, destroy removes, both scoped to own actor" do
    json = create_snap
    patch "/stack_snapshots/#{json['id']}", params: { pinned: true }, as: :json
    assert_response :ok
    assert StackSnapshot.find(json["id"]).pinned

    delete "/stack_snapshots/#{json['id']}"
    assert_response :no_content
    assert_not StackSnapshot.exists?(json["id"])
  end

  test "foreign snapshot ids are not reachable" do
    eve = create_human(password: "secretsecret")
    foreign = StackSnapshot.record!(actor: eve, history_key: @key, trail: [["fremd"]], current: 0)
    patch "/stack_snapshots/#{foreign.id}", params: { pinned: true }, as: :json
    assert_response :not_found
    delete "/stack_snapshots/#{foreign.id}"
    assert_response :not_found
    assert StackSnapshot.exists?(foreign.id)
  end

  test "create with empty trail is unprocessable" do
    post "/stack_snapshots", params: { key: @key, trail: [], current: 0 }, as: :json
    assert_response :unprocessable_entity
  end
end
