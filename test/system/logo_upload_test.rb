require "application_system_test_case"

# #1211: Logo-Upload über das ECHTE Formular. Der Controller-Test postet
# multipart direkt — dass das Formular selbst kein multipart-enctype
# hatte (Datei kam als String an, 500, „Content missing"), konnte nur
# ein Test durchs UI sehen.
class LogoUploadTest < ApplicationSystemTestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update])
    grant(@hans, "Topic", %w[read])

    @tmp_base = Pathname.new(Dir.mktmpdir("miolim-systest-"))
    @original_base = FileProxy::BASE_PATH
    FileProxy.send(:remove_const, :BASE_PATH)
    FileProxy.const_set(:BASE_PATH, @tmp_base)

    uuid = SecureRandom.uuid
    rel  = "knowledge/organizations/logofirma.md"
    FileUtils.mkdir_p(@tmp_base.join("knowledge/organizations"))
    File.write(@tmp_base.join(rel),
      "---\nid: #{uuid}\ntype: organization\n---\n\n# Logofirma\n\n")
    @org = KnowledgeItem.create!(
      uuid: uuid, title: "Logofirma", item_type: "organization",
      creator: @hans, file_path: rel, content_hash: "h-logofirma"
    )

    @png_path = @tmp_base.join("logo.png")
    File.binwrite(@png_path, "\x89PNG\r\n\x1a\nfakepixels")

    login_as(@hans)
  end

  teardown do
    if @original_base
      FileProxy.send(:remove_const, :BASE_PATH)
      FileProxy.const_set(:BASE_PATH, @original_base)
    end
    FileUtils.remove_entry(@tmp_base) if @tmp_base&.exist?
  end

  test "#1211 Logo-Upload über das Formular zeigt das Thumbnail (kein Content missing)" do
    visit "/knowledge_items?stack=#{@org.uuid}"
    assert page.has_css?("article.stack-card[data-uuid='#{@org.uuid}']")

    # Tri-Disclosure: closed → belegte Felder → alle Felder (Logo ist leer).
    2.times { find("button", text: "Details", match: :first).click }
    assert page.has_css?("#ki_logo_#{@org.uuid}", visible: :all)

    within("#ki_logo_#{@org.uuid}") do
      attach_file("file", @png_path.to_s, make_visible: true)
    end

    assert page.has_css?("#ki_logo_#{@org.uuid} img"),
           "Nach dem Upload muss das Logo-Thumbnail erscheinen"
    assert_equal KnowledgeItem.find_by(title: "Logo Logofirma").uuid,
                 @org.reload.logo_uuid
    refute page.has_text?("Content missing")
  end
end
