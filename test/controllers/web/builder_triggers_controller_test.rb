require "test_helper"

class BuilderTriggersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-bt-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Actor", %w[read update])
    post "/login", params: { email: @hans.email, password: "secretsecret" }

    @builder = AgentActor.create!(name: "Builder-#{SecureRandom.hex(3)}", description: "test")
  end

  test "POST stamps inbox_run_requested_at and renders toast" do
    assert_nil @builder.reload.inbox_run_requested_at
    post "/builders/#{@builder.id}/request_inbox_run",
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :ok
    assert_not_nil @builder.reload.inbox_run_requested_at
    assert_includes @response.body, "toast_stack"
    assert_includes @response.body, @builder.name
  end

  test "POST as HTML redirects back with notice" do
    post "/builders/#{@builder.id}/request_inbox_run",
         headers: { "Referer" => "/dashboard" }
    assert_redirected_to "/dashboard"
    assert_not_nil @builder.reload.inbox_run_requested_at
  end

  test "without Actor.update capability is forbidden" do
    no_caps = HumanActor.create!(
      name: "No", email: "no-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    post "/login", params: { email: no_caps.email, password: "secretsecret" }
    post "/builders/#{@builder.id}/request_inbox_run"
    assert_response :forbidden
    assert_nil @builder.reload.inbox_run_requested_at
  end
end
