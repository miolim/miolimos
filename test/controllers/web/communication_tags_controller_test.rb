require "test_helper"

# #801 P1: Web-Tests für /communications/:id/tags (#695) — string[]-Spalte,
# Add/Remove als Array-Operation, Spiegel des TaskTagsController.
class CommunicationTagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-ct-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Communication", %w[read update])
    post "/login", params: { email: @hans.email, password: "secretsecret" }

    @comm = Communication.create!(direction: "inbound", subject: "Probe-Mail",
                                  external_id: "ct-#{SecureRandom.hex(4)}")
    # Write-Guard (#602): schreibbar nur über ein für den Actor schreibbares
    # Topic (Communications haben keinen creator).
    topic = create_topic(creator: @hans)
    CommunicationTopic.create!(communication: @comm, topic: topic)
  end

  test "POST adds normalized tag (downcase + strip)" do
    post "/communications/#{@comm.id}/tags",
         params: { create_with: "  Wichtig  " },
         headers: { "Accept" => "application/json" }
    assert_response :ok
    assert_equal ["wichtig"], @comm.reload.tags
  end

  test "POST with existing tag does not duplicate" do
    @comm.update!(tags: ["wichtig"])
    post "/communications/#{@comm.id}/tags",
         params: { tag_id: "WICHTIG" },
         headers: { "Accept" => "application/json" }
    assert_response :ok
    assert_equal ["wichtig"], @comm.reload.tags
  end

  test "POST with blank tag returns unprocessable" do
    post "/communications/#{@comm.id}/tags",
         params: { create_with: "   " },
         headers: { "Accept" => "application/json" }
    assert_response :unprocessable_entity
    assert_empty Array(@comm.reload.tags)
  end

  test "POST renders chips turbo-stream" do
    post "/communications/#{@comm.id}/tags",
         params: { create_with: "projekt" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :ok
    assert_includes @response.body, "comm_tags_chips_#{@comm.id}"
  end

  test "DELETE removes tag" do
    @comm.update!(tags: %w[wichtig projekt])
    delete "/communications/#{@comm.id}/tags/wichtig",
           headers: { "Accept" => "application/json" }
    assert_response :ok
    assert_equal ["projekt"], @comm.reload.tags
  end

  test "DELETE with unknown tag leaves tags untouched" do
    @comm.update!(tags: ["projekt"])
    delete "/communications/#{@comm.id}/tags/gibtsnicht",
           headers: { "Accept" => "application/json" }
    assert_response :ok
    assert_equal ["projekt"], @comm.reload.tags
  end

  test "without update capability requests are forbidden" do
    eve = create_human(password: "secretsecret")
    grant(eve, "Communication", %w[read])
    post "/login", params: { email: eve.email, password: "secretsecret" }
    post "/communications/#{@comm.id}/tags",
         params: { create_with: "x" },
         headers: { "Accept" => "application/json" }
    assert_response :forbidden
  end
end
