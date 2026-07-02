require "test_helper"

# #633: E-Mail-Anhänge — Anzeige am Kommunikations-Blade + Übernahme in
# die Inbox mit Provenienz (payload.communication_id) und Topic-Erbe.
class CommunicationAttachmentsTest < ActionDispatch::IntegrationTest
  setup do
    @hans = create_human(password: "secretsecret")
    %w[Communication InboxItem Topic KnowledgeItem Task].each do |rt|
      grant(@hans, rt, %w[read create update delete])
    end
    post "/login", params: { email: @hans.email, password: "secretsecret" }

    @cred = OauthCredential.create!(actor: @hans, provider: "google",
                                    email_address: "att-#{SecureRandom.hex(3)}@t.local")
    @topic = Topic.create!(name: "Mail-Thema", slug: "mail-#{SecureRandom.hex(3)}", creator: @hans)
    @comm = Email.create!(
      subject: "Rechnung Mai", body: "Anbei.", direction: :inbound,
      external_id: "msg-#{SecureRandom.hex(4)}", oauth_credential: @cred,
      sent_at: Time.current,
      raw_data: { "payload" => { "parts" => [
        { "mime_type" => "text/plain", "filename" => "",
          "body" => { "size" => 10 } },
        { "mime_type" => "application/pdf", "filename" => "rechnung-mai.pdf",
          "body" => { "size" => 12_345, "attachment_id" => "ATT123" } }
      ] } }
    )
    @comm.topics << @topic
  end

  test "Communication#attachments liest Metadaten aus raw_data" do
    atts = @comm.attachments
    assert_equal 1, atts.size
    assert_equal "rechnung-mai.pdf", atts[0][:filename]
    assert_equal "application/pdf",  atts[0][:mime_type]
    assert_equal 12_345,             atts[0][:size]
    assert_equal "ATT123",           atts[0][:attachment_id]
  end

  test "Kommunikations-Blade zeigt Anhangsliste mit Import-Button" do
    get "/communications/#{@comm.id}/card"
    assert_response :success
    assert_includes @response.body, "Anhänge"
    assert_includes @response.body, "rechnung-mai.pdf"
    assert_includes @response.body, "In Inbox übernehmen"
  end

  test "Import erzeugt InboxItem mit Provenienz + Topic-Erbe; Blade zeigt danach den Link" do
    stub_fetch("PDFBYTES") do
      assert_difference -> { InboxItem.count }, 1 do
        post "/communications/#{@comm.id}/attachments/import",
             params: { index: 0, stay_in_stack: 1 },
             headers: { "Referer" => "http://www.example.com/communications?stack=list:communications,communication:#{@comm.id}" }
      end
    end
    item = InboxItem.order(:id).last
    assert_equal "rechnung-mai", item.title
    assert_equal "pdf_upload",   item.source_kind
    assert_equal @comm.id,       item.payload["communication_id"]
    assert_equal 0,              item.payload["attachment_index"]
    assert_equal [@topic.id],    item.topics.pluck(:id)
    assert_equal "PDFBYTES",     File.binread(item.external_path)

    # stay_in_stack: zurück auf den Referer-Stack + neues Blade.
    assert_response :redirect
    assert_includes @response.redirect_url, "/communications?stack="
    assert_includes @response.redirect_url, "inboxitem%3A#{item.id}"

    # Blade zeigt jetzt den Inbox-Link statt des Import-Buttons.
    get "/communications/#{@comm.id}/card"
    assert_includes @response.body, "in Inbox"
    refute_includes @response.body, "In Inbox übernehmen"

    # Inbox-Detail zeigt die Provenienz zur Mail.
    get "/inbox/#{item.id}/card"
    assert_includes @response.body, "aus E-Mail:"
    assert_includes @response.body, "Rechnung Mai"
  ensure
    item = InboxItem.order(:id).last
    File.delete(item.external_path) if item&.external_path && File.exist?(item.external_path)
  end

  test "Doppel-Import legt kein zweites Item an" do
    stub_fetch("PDFBYTES") do
      post "/communications/#{@comm.id}/attachments/import", params: { index: 0 }
      assert_no_difference -> { InboxItem.count } do
        post "/communications/#{@comm.id}/attachments/import", params: { index: 0 }
      end
    end
  ensure
    item = InboxItem.order(:id).last
    File.delete(item.external_path) if item&.external_path && File.exist?(item.external_path)
  end

  test "unbekannter Index ist 404; ohne InboxItem-create-Capability 403" do
    post "/communications/#{@comm.id}/attachments/import", params: { index: 7 }
    assert_response :not_found

    delete "/logout"
    reader = create_human(name: "Leser", password: "secretsecret")
    grant(reader, "Communication", %w[read])
    post "/login", params: { email: reader.email, password: "secretsecret" }
    post "/communications/#{@comm.id}/attachments/import", params: { index: 0 }
    assert_response :forbidden
  end

  private

  # GmailSync.fetch_attachment von Hand stubben (minitest/mock ist in
  # Minitest 6 ein eigenes Gem, s. fetch_inbox_title_job_test).
  def stub_fetch(bytes)
    original = GmailSync.method(:fetch_attachment)
    GmailSync.define_singleton_method(:fetch_attachment) { |*_a| bytes }
    yield
  ensure
    GmailSync.define_singleton_method(:fetch_attachment, original)
  end
end
