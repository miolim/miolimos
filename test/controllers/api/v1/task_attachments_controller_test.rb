require "test_helper"

# #203: Coverage fuer den Agenten-Bearer-Stream-Pfad (#182).
class Api::V1::TaskAttachmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = create_human
    grant(@hans, "Task", %w[read create update delete])
    @agent = AgentActor.create!(name: "Bot-#{SecureRandom.hex(2)}",
                                 description: "test", active: true)
    grant(@agent, "Task", %w[read])
    @auth = { "Authorization" => "Bearer #{@agent.api_token}" }
  end

  def make_upload(filename: "shot.png", content: "PNGDATA", type: "image/png")
    Rack::Test::UploadedFile.new(StringIO.new(content), type, original_filename: filename)
  end

  test "GET liefert die hinterlegte Datei mit korrektem Content-Type" do
    with_isolated_miolimos_base do
      task = Task.create!(title: "Mit Attachment", creator: @hans, assignee: @hans)
      # Direkt ueber den Web-Pfad als Hans hochladen (loggt sich ein und legt die Datei an).
      hans_human = HumanActor.create!(name: "Uploader",
                                       email: "u-#{SecureRandom.hex(3)}@t.local",
                                       password: "secretsecret")
      grant(hans_human, "Task", %w[read create update delete])
      post "/login", params: { email: hans_human.email, password: "secretsecret" }
      post "/tasks/#{task.id}/attachments",
           params: { file: make_upload(filename: "diagram.png", content: "PNGBODY") },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      attachment = task.attachments.last
      assert attachment, "Setup-Upload muss geklappt haben"

      # Logout, dann via Bearer-Token zugreifen
      delete "/logout"
      get "/api/v1/tasks/#{task.id}/attachments/#{attachment.id}", headers: @auth
      assert_response :success
      assert_equal "image/png", response.media_type
      assert_equal "PNGBODY", response.body
    end
  end

  test "GET unbekanntes Attachment auf bekanntem Task liefert 404 (json)" do
    with_isolated_miolimos_base do
      task = Task.create!(title: "Leer", creator: @hans, assignee: @hans)
      get "/api/v1/tasks/#{task.id}/attachments/999999", headers: @auth
      assert_response :not_found
    end
  end

  test "GET ohne Authorization-Header schlaegt fehl" do
    task = Task.create!(title: "X", creator: @hans, assignee: @hans)
    get "/api/v1/tasks/#{task.id}/attachments/1"
    assert_response :unauthorized
  end

  test "Agent ohne read-Capability auf Task ist gesperrt" do
    no_caps = AgentActor.create!(name: "NoCaps-#{SecureRandom.hex(2)}",
                                  description: "test", active: true)
    task = Task.create!(title: "X", creator: @hans, assignee: @hans)
    get "/api/v1/tasks/#{task.id}/attachments/1",
        headers: { "Authorization" => "Bearer #{no_caps.api_token}" }
    assert_response :forbidden
  end

  # #774: Upload per API
  test "POST create hängt eine Datei an (Agent mit update)" do
    with_isolated_miolimos_base do
      writer = AgentActor.create!(name: "Writer-#{SecureRandom.hex(2)}", description: "test", active: true)
      grant(writer, "Task", %w[read update])
      task = Task.create!(title: "Ziel", creator: @hans, assignee: @hans)
      assert_difference -> { task.attachments.count }, 1 do
        post "/api/v1/tasks/#{task.id}/attachments",
             params: { file: make_upload(filename: "berlin.png", content: "IMGBYTES", type: "image/png") },
             headers: { "Authorization" => "Bearer #{writer.api_token}" }
      end
      assert_response :created
      body = JSON.parse(response.body)
      assert_equal "berlin.png", body.dig("data", "original_filename")
      assert_equal "image/png",  body.dig("data", "content_type")
      assert_equal "IMGBYTES", File.read(task.attachments.last.full_path)
    end
  end

  test "POST create ohne Datei liefert 422" do
    with_isolated_miolimos_base do
      writer = AgentActor.create!(name: "Writer2-#{SecureRandom.hex(2)}", description: "test", active: true)
      grant(writer, "Task", %w[read update])
      task = Task.create!(title: "Ziel", creator: @hans, assignee: @hans)
      post "/api/v1/tasks/#{task.id}/attachments",
           headers: { "Authorization" => "Bearer #{writer.api_token}" }
      assert_response :unprocessable_entity
    end
  end

  test "POST create braucht update-Capability (read reicht nicht)" do
    with_isolated_miolimos_base do
      task = Task.create!(title: "Ziel", creator: @hans, assignee: @hans)
      post "/api/v1/tasks/#{task.id}/attachments",
           params: { file: make_upload }, headers: @auth
      assert_response :forbidden
    end
  end
end
