require "application_system_test_case"

# #1453 (aus immoos #1452 übernommen). Hans dort: „Bei Tap auf die Zahlen
# öffnet sich eine Ansicht mit allen Spines, der aktuelle Spine ist
# hervorgehoben. Durch Tap auf einen Spine wird dieser geöffnet."
#
# Nur im mobilen Bild prüfbar: Die Zahlen sind auf dem Schreibtisch
# ausgeblendet (md:hidden).
class StackOverviewTest < ApplicationSystemTestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update])
    grant(@hans, "Task", %w[read])

    @tmp_base = Pathname.new(Dir.mktmpdir("miolim-overview-"))
    @original_base = FileProxy::BASE_PATH
    FileProxy.send(:remove_const, :BASE_PATH)
    FileProxy.const_set(:BASE_PATH, @tmp_base)

    FileUtils.mkdir_p(@tmp_base.join("knowledge/notes"))
    @items = %w[alpha beta].map do |name|
      uuid = SecureRandom.uuid
      rel  = "knowledge/notes/#{name}.md"
      File.write(@tmp_base.join(rel), "---\nid: #{uuid}\ntype: note\n---\n\n# #{name}\n")
      KnowledgeItem.create!(uuid: uuid, title: name.capitalize, item_type: "note",
                            creator: @hans, file_path: rel, content_hash: "h-#{name}")
    end
    login_as(@hans)
  end

  teardown do
    if @original_base
      FileProxy.send(:remove_const, :BASE_PATH)
      FileProxy.const_set(:BASE_PATH, @original_base)
    end
    FileUtils.remove_entry(@tmp_base) if @tmp_base&.exist?
  end

  test "die Zahl öffnet die Liste der offenen Cards" do
    page.driver.resize_window(390, 780)
    # Listen-Blade dazu, damit zwei verschiedene Spine-Farben im Spiel sind.
    visit "/knowledge_items?stack=list:knowledge_items,#{@items[0].uuid},#{@items[1].uuid}"
    assert_selector "article.stack-card[data-uuid='#{@items[1].uuid}']", wait: 10

    # Vorbedingung: Die Übersicht ist zu, bevor jemand tippt.
    assert_no_selector "[data-stack-overview-target='blatt']:not(.hidden)"

    find("[data-blade-counts-target='left']").click
    assert_selector "[data-stack-overview-target='blatt']:not(.hidden)", wait: 5

    eintraege = all("[data-stack-overview-target='liste'] button")
    assert_equal 3, eintraege.size, "jede offene Card bekommt eine Zeile"
    assert_equal 1, all("[data-stack-overview-target='liste'] button.bg-sky-50").size,
                 "genau eine Zeile ist die aktuelle"

    # Zeichen und Farbe werden vom Kartenrücken übernommen, nicht neu bestimmt.
    # Geprüft wird, dass sie wirklich ankommen — und dass die Farben sich
    # unterscheiden, sonst wäre die Übernahme wirkungslos.
    befund = page.evaluate_script(<<~JS)
      (() => {
        const zeilen = Array.from(document.querySelectorAll("[data-stack-overview-target='liste'] button"));
        return zeilen.map(z => {
          const balken = z.querySelector("span");
          return { svg: !!z.querySelector("svg"), farbe: balken ? balken.style.backgroundColor : null };
        });
      })()
    JS
    assert befund.all? { |b| b["svg"] }, "jede Zeile trägt das Zeichen ihrer Card"
    assert befund.all? { |b| b["farbe"].present? }, "und die Farbe ihres Spines"
    assert_operator befund.map { |b| b["farbe"] }.uniq.size, :>=, 2,
                    "Listen- und Detail-Cards haben verschiedene Spine-Farben — das muss man sehen"

    # Tap auf eine Zeile schließt die Übersicht und springt zur Card.
    eintraege.first.click
    assert_no_selector "[data-stack-overview-target='blatt']:not(.hidden)", wait: 5
  end

  test "der rechte Zähler öffnet dieselbe Liste" do
    page.driver.resize_window(390, 780)
    visit "/knowledge_items?stack=#{@items[0].uuid},#{@items[1].uuid}"
    assert_selector "article.stack-card[data-uuid='#{@items[1].uuid}']", wait: 10

    find("[data-blade-counts-target='right']").click
    assert_selector "[data-stack-overview-target='blatt']:not(.hidden)", wait: 5
    assert_equal 2, all("[data-stack-overview-target='liste'] button").size
  end
end
