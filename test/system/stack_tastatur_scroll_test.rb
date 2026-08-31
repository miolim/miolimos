require "application_system_test_case"

# #1486 (Hans): „Wenn ich im Stack per Tastatur zu einer anderen Card
# navigiere, wird der Vertikal-Scroll-Fokus nicht mitgenommen."
#
# Warum das ueberhaupt passiert: Welche Card die Pfeiltasten scrollen,
# entscheidet nicht `data-active`, sondern der DOM-Fokus — der Browser
# scrollt den naechsten scrollbaren Vorfahren des fokussierten Elements.
# Ein Mausklick setzt diesen Fokus nebenbei mit (deshalb funktioniert es
# nach dem Klicken), Strg+Alt+Pfeil hat ihn bisher nicht angefasst. Der
# Fokus blieb also auf der ALTEN Card stehen, und ↓ scrollte weiter dort.
#
# Getestet wird mit ECHTEN Tastendruecken, nicht mit synthetischen
# KeyboardEvents: Das Scrollen ist Browser-Verhalten, kein Code von uns —
# ein `dispatchEvent` wuerde zwar unseren Handler ausloesen, aber nie
# etwas scrollen. Der Test bewiese dann nichts.
class StackTastaturScrollTest < ApplicationSystemTestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update])
    grant(@hans, "Task", %w[read])

    @tmp_base = Pathname.new(Dir.mktmpdir("miolim-tastatur-"))
    @original_base = FileProxy::BASE_PATH
    FileProxy.send(:remove_const, :BASE_PATH)
    FileProxy.const_set(:BASE_PATH, @tmp_base)
    FileUtils.mkdir_p(@tmp_base.join("knowledge/notes"))

    # Lang genug, dass beide Cards wirklich scrollen koennen — sonst
    # bliebe scrollTop auch bei richtigem Fokus null und der Test waere
    # gruen, ohne etwas zu zeigen.
    @items = %w[alpha beta].map do |name|
      uuid = SecureRandom.uuid
      rel  = "knowledge/notes/#{name}.md"
      absaetze = Array.new(60) { |i| "Absatz #{i} von #{name}. #{'Fuelltext ' * 12}" }.join("\n\n")
      File.write(@tmp_base.join(rel),
                 "---\nid: #{uuid}\ntype: note\n---\n\n# #{name.capitalize}\n\n#{absaetze}\n")
      KnowledgeItem.create!(uuid: uuid, title: name.capitalize, item_type: "note",
                            creator: @hans, file_path: rel, content_hash: "h-#{name}")
    end
    @alpha, @beta = @items

    login_as(@hans)
  end

  teardown do
    if @original_base
      FileProxy.send(:remove_const, :BASE_PATH)
      FileProxy.const_set(:BASE_PATH, @original_base)
    end
    FileUtils.remove_entry(@tmp_base) if @tmp_base&.exist?
  end

  def stack_oeffnen
    # Klein genug, dass der Inhalt einer Card wirklich ueberlaeuft — sonst
    # bliebe scrollTop auch bei richtigem Fokus null, und der Test waere
    # gruen, ohne etwas gezeigt zu haben.
    page.driver.resize_window(1200, 400)
    visit "/knowledge_items?stack=#{@alpha.uuid},#{@beta.uuid}"
    assert_selector "article.stack-card[data-uuid='#{@beta.uuid}']", wait: 10
    # Ausgangslage: die zuletzt geoeffnete Card ist aktiv.
    assert_equal @beta.uuid, aktive_uuid
  end

  def aktive_uuid
    page.evaluate_script(
      "document.querySelector('.stack-card[data-active=\"true\"]')?.dataset.uuid"
    )
  end

  # scrollTop des Inhaltsbereichs einer Card.
  def scroll_von(uuid)
    page.evaluate_script(<<~JS)
      (() => {
        const card = document.querySelector('.stack-card[data-uuid="#{uuid}"]');
        const box  = card && card.querySelector(":scope > .overflow-y-auto");
        return box ? Math.round(box.scrollTop) : -1;
      })()
    JS
  end

  # Tasten OHNE Umweg über ein Element. `find("body").send_keys` waere hier
  # falsch: Cuprite KLICKT den Knoten vorher an (`page.rb#send_keys` ruft
  # `node.click`, wenn die Auswahl nicht schon drinliegt). Der Klick landet
  # in der Mitte des Fensters, also mitten in einer Card, fokussiert dort
  # einen Knopf und setzt ueber den focusin-Handler die aktive Card um.
  # Der Test haette dann gemessen, was der Klick tut, nicht was die Taste
  # tut — und genau daran bin ich beim ersten Anlauf haengengeblieben.
  def taste(*keys)
    page.driver.browser.page.keyboard.type(*keys)
  end

  test "der Scroll-Fokus wandert mit der aktiven Card" do
    stack_oeffnen
    taste([:ctrl, :alt, :left])
    assert_equal @alpha.uuid, aktive_uuid, "Strg+Alt+Links wechselt die aktive Card"

    5.times { taste(:down) }

    assert_operator scroll_von(@alpha.uuid), :>, 0,
                    "die jetzt aktive Card muss scrollen"
    assert_equal 0, scroll_von(@beta.uuid),
                 "und die vorher aktive darf es nicht mehr tun"
  end

  # Die Gegenrichtung, damit der Test nicht nur „irgendwo landet der
  # Fokus schon" prueft: Wer zurueckwechselt, scrollt wieder die andere.
  test "zurueckwechseln nimmt den Scroll-Fokus wieder mit" do
    stack_oeffnen
    taste([:ctrl, :alt, :left])
    5.times { taste(:down) }
    vorher = scroll_von(@alpha.uuid)

    taste([:ctrl, :alt, :right])
    assert_equal @beta.uuid, aktive_uuid
    5.times { taste(:down) }

    assert_operator scroll_von(@beta.uuid), :>, 0, "jetzt scrollt Beta"
    assert_equal vorher, scroll_von(@alpha.uuid), "und Alpha bleibt stehen, wo es stand"
  end

  # Der Fokus soll den Inhaltsbereich treffen, nicht irgendein Element
  # darin. Sonst haengt das Scrollen davon ab, was zufaellig fokussierbar
  # ist — bei einer Card ohne Link waere es wieder nichts.
  test "der Fokus sitzt auf dem Inhaltsbereich der aktiven Card" do
    stack_oeffnen
    taste([:ctrl, :alt, :left])

    befund = page.evaluate_script(<<~JS)
      (() => {
        const el   = document.activeElement;
        const card = el && el.closest(".stack-card");
        return {
          uuid:      card ? card.dataset.uuid : null,
          istKasten: !!(el && el.matches(".stack-card > .overflow-y-auto"))
        };
      })()
    JS

    assert_equal @alpha.uuid, befund["uuid"], "der Fokus steht in der aktiven Card"
    assert befund["istKasten"], "und zwar auf ihrem scrollbaren Inhaltsbereich"
  end
end
