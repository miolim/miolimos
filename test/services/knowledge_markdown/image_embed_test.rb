require "test_helper"

class KnowledgeMarkdown::ImageEmbedTest < ActiveSupport::TestCase
  setup do
    @hans = create_human(email: "kme-#{SecureRandom.hex(3)}@t.local")
    grant(@hans, "KnowledgeItem", %w[read create])
  end

  test "embed of an image-typed KI renders as <img>, not body-inline" do
    with_isolated_miolimos_base do
      Current.actor = @hans
      png = Rack::Test::UploadedFile.new(
        StringIO.new("PNGDATA"), "image/png", original_filename: "photo.png"
      )
      ki = FileProxy.create_with_file(actor: @hans, title: "Foto",
                                      uploaded_io: png, item_type: :transcript)
      assert ki.file_path.end_with?(".png"), "expected image extension"

      html = KnowledgeMarkdown.render("![[Foto]]")
      assert_match %r{<img src="/knowledge_items/#{ki.uuid}/file"}, html
      assert_match %r{<figure class="my-3">},                       html
      refute_match %r{<aside class="embed},                         html
    end
  end

  test "embed of a markdown KI still uses body-inline embed (no img)" do
    with_isolated_miolimos_base do
      Current.actor = @hans
      ki = FileProxy.create(actor: @hans, title: "Notiz", item_type: :note,
                            content: "Inhalt der Notiz.")
      html = KnowledgeMarkdown.render("![[Notiz]]")
      refute_match %r{<img }, html
      assert_match %r{<aside class="embed}, html
      assert_match %r{Inhalt der Notiz}, html
    end
  end

  test "image embed with caption renders <figcaption>" do
    with_isolated_miolimos_base do
      Current.actor = @hans
      png = Rack::Test::UploadedFile.new(
        StringIO.new("PNGDATA"), "image/png", original_filename: "photo.png"
      )
      ki = FileProxy.create_with_file(actor: @hans, title: "Mein Foto",
                                      uploaded_io: png, item_type: :transcript)
      html = KnowledgeMarkdown.render("![[Mein Foto#Bildunterschrift]]")
      assert_match %r{<figcaption[^>]*>Bildunterschrift</figcaption>}, html
    end
  end
end
