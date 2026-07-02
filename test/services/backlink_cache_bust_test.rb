require "test_helper"

# #663: Wenn ein KI einen Block-Anker eines anderen KI rückverlinkt,
# muss dessen Render-Cache verworfen werden — sonst zeigt die markierte
# Stelle bis zum 12h-TTL keinen Backlink-Indikator auf das Ergebnis.
class BacklinkCacheBustTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    # Test-Env nutzt :null_store — echten Cache einsetzen, sonst lässt
    # sich das Busting nicht prüfen.
    @prev_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = @prev_cache }

  test "neues Rückverweis-KI bustet den Render-Cache der Quelle → Backlink erscheint" do
    with_isolated_miolimos_base do
      source = FileProxy.create(actor: @hans, title: "Quelle mit Highlight", item_type: :note,
                                content: "Ein ==rot|wichtiger Satz==^a1b2c3d4 im Text.")
      # Erst-Render füllt den Cache — noch ohne Backlink.
      first = KnowledgeMarkdown.render(source.body, item: source.reload)
      assert_equal 0, first.scan(/backlink-indicator/).size

      # Ergebnis-KI verlinkt den Anker zurück.
      FileProxy.create(actor: @hans, title: "Rechercheergebnis", item_type: :note,
                       content: "Antwort. Siehe [[Quelle mit Highlight^a1b2c3d4]].")

      # Ohne Busting läge hier noch der alte (leere) Cache-Eintrag.
      again = KnowledgeMarkdown.render(source.reload.body, item: source)
      assert_equal 1, again.scan(/backlink-indicator/).size,
                   "Quelle muss nach Rückverweis den Backlink-Indikator zeigen"
    end
  end

  test "bust_cache ist no-op für nil / nicht-persistierte Items" do
    assert_nil KnowledgeMarkdown.bust_cache(nil)
    assert_nil KnowledgeMarkdown.bust_cache(KnowledgeItem.new)
  end
end
