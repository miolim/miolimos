require "test_helper"

class TaskAttachmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-att-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Task", %w[read create update delete])
    post "/login", params: { email: @hans.email, password: "secretsecret" }

    @task = Task.create!(title: "Tu was", creator: @hans, assignee: @hans, status: :open)
  end

  def make_upload(filename: "screenshot.png", content: "PNGDATA", type: "image/png")
    Rack::Test::UploadedFile.new(
      StringIO.new(content), type, original_filename: filename
    )
  end

  test "POST create stores file under task_attachments/<id>/ and records DB row" do
    with_isolated_miolimos_base do |base|
      assert_difference -> { TaskAttachment.count }, 1 do
        post "/tasks/#{@task.id}/attachments",
             params: { file: make_upload },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_response :ok

      att = @task.attachments.last
      assert_equal "screenshot.png", att.original_filename
      assert_equal "image/png",      att.content_type
      assert att.byte_size.positive?
      assert_equal @hans.id,         att.uploader_id

      stored = base.join(att.file_path)
      assert stored.exist?, "file should exist on disk at #{stored}"
      assert_match %r{task_attachments/#{@task.id}/[a-f0-9]{8}-screenshot\.png}, att.file_path
      assert_includes @response.body, "task_attachments_#{@task.id}"
    end
  end

  test "POST create without file shows alert and creates nothing" do
    with_isolated_miolimos_base do
      assert_no_difference -> { TaskAttachment.count } do
        post "/tasks/#{@task.id}/attachments", headers: { "Referer" => "/tasks/#{@task.id}" }
      end
      assert_redirected_to "/tasks/#{@task.id}"
    end
  end

  test "POST create sanitizes weird characters in original filename" do
    with_isolated_miolimos_base do |base|
      upload = make_upload(filename: "../weird; name with spaces.png")
      post "/tasks/#{@task.id}/attachments",
           params: { file: upload },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      att = @task.attachments.last
      # The stored filename has no slashes / spaces / semicolons.
      stored_basename = File.basename(att.file_path)
      refute_match %r{\.\.|/|;|\s}, stored_basename
      assert base.join(att.file_path).exist?
    end
  end

  test "GET show streams the file inline for images" do
    with_isolated_miolimos_base do |base|
      post "/tasks/#{@task.id}/attachments",
           params: { file: make_upload(filename: "shot.png", content: "PNGDATA") },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      att = @task.attachments.last

      get "/tasks/#{@task.id}/attachments/#{att.id}"
      assert_response :ok
      assert_includes response.headers["Content-Disposition"], "inline"
      assert_equal "image/png", response.headers["Content-Type"]
    end
  end

  test "GET show streams unknown types as attachment" do
    with_isolated_miolimos_base do
      post "/tasks/#{@task.id}/attachments",
           params: { file: make_upload(filename: "log.txt", content: "hi", type: "text/plain") },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      att = @task.attachments.last

      get "/tasks/#{@task.id}/attachments/#{att.id}"
      assert_response :ok
      assert_includes response.headers["Content-Disposition"], "attachment"
    end
  end

  test "DELETE removes DB row and underlying file" do
    with_isolated_miolimos_base do |base|
      post "/tasks/#{@task.id}/attachments",
           params: { file: make_upload },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      att = @task.attachments.last
      stored = base.join(att.file_path)
      assert stored.exist?

      assert_difference -> { TaskAttachment.count }, -1 do
        delete "/tasks/#{@task.id}/attachments/#{att.id}",
               headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_response :ok
      refute stored.exist?, "underlying file should be removed too"
    end
  end

  test "without Task.update capability, upload is forbidden" do
    with_isolated_miolimos_base do
      read_only = HumanActor.create!(
        name: "RO", email: "ro-att-#{SecureRandom.hex(3)}@t.local",
        password: "secretsecret"
      )
      grant(read_only, "Task", %w[read])
      post "/login", params: { email: read_only.email, password: "secretsecret" }

      post "/tasks/#{@task.id}/attachments", params: { file: make_upload }
      assert_response :forbidden
    end
  end
end
