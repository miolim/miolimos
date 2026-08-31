require "application_system_test_case"

# #1453 (aus immoos #1451 übernommen). Hans dort: „mobil wird der Card Spine
# oben quer angezeigt. Dort sind entweder die Inhalte etwas nach oben
# verschoben … Dadurch sieht es so aus, als wäre die Zeile im Spine nicht
# vertikal zentriert."
#
# Zwei Ursachen, die denselben Eindruck machen:
#   1. Die Trennlinie unten zählt zur HÖHE der Box, aber nicht zum
#      Inhaltsbereich, in dem zentriert wird (ein Pixel).
#   2. Der eigentliche Grund: Der Stapel zog sich mobil mit einem zu großen
#      negativen Margin nach oben und rutschte 8 px UNTER die Topbar — vom
#      36 px hohen Spine blieben 29 sichtbar, und weil der Inhalt in den
#      vollen 36 zentriert ist, saß er im sichtbaren Rest zu weit oben.
#
# Der erste Test misst deshalb INNEN, der zweite AUSSEN. Nur zusammen decken
# sie ab, was zu sehen war: Der erste allein blieb grün, während der Balken
# angeschnitten war.
class SpineMobilTest < ApplicationSystemTestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update])
    grant(@hans, "Task", %w[read])

    @tmp_base = Pathname.new(Dir.mktmpdir("miolim-spine-"))
    @original_base = FileProxy::BASE_PATH
    FileProxy.send(:remove_const, :BASE_PATH)
    FileProxy.const_set(:BASE_PATH, @tmp_base)

    uuid = SecureRandom.uuid
    rel  = "knowledge/notes/spine.md"
    FileUtils.mkdir_p(@tmp_base.join("knowledge/notes"))
    File.write(@tmp_base.join(rel), "---\nid: #{uuid}\ntype: note\n---\n\n# Spine\n\nInhalt.\n")
    @ki = KnowledgeItem.create!(uuid: uuid, title: "Spine", item_type: "note",
                                creator: @hans, file_path: rel, content_hash: "h-spine")
    login_as(@hans)
  end

  teardown do
    if @original_base
      FileProxy.send(:remove_const, :BASE_PATH)
      FileProxy.const_set(:BASE_PATH, @original_base)
    end
    FileUtils.remove_entry(@tmp_base) if @tmp_base&.exist?
  end

  def mobil_oeffnen
    page.driver.resize_window(390, 780)
    visit "/knowledge_items?stack=#{@ki.uuid}"
    assert_selector "article.stack-card .stack-spine", wait: 10
  end

  test "der Inhalt des Spines sitzt mobil mittig" do
    mobil_oeffnen

    abstaende = page.evaluate_script(<<~JS)
      (() => {
        const spine = document.querySelector("article.stack-card .stack-spine");
        const r = spine.getBoundingClientRect();
        return Array.from(spine.children).map(k => {
          const kr = k.getBoundingClientRect();
          return Math.round(kr.top - r.top) - Math.round(r.bottom - kr.bottom);
        });
      })()
    JS

    assert abstaende.any?, "der Spine trägt Inhalt"
    abstaende.each do |diff|
      assert_equal 0, diff,
                   "oben und unten müssen gleich viel Luft haben (Differenz #{diff} px)"
    end
  end

  test "der Spine steht vollständig unter der Topbar" do
    mobil_oeffnen

    mass = page.evaluate_script(<<~JS)
      (() => {
        const spine = document.querySelector("article.stack-card .stack-spine");
        const topbar = Array.from(document.querySelectorAll("header"))
                            .find(h => h.getBoundingClientRect().top === 0 &&
                                       h.getBoundingClientRect().height > 0);
        const cont = document.getElementById("blade_stack_container");
        const s = spine.getBoundingClientRect(), c = cont.getBoundingClientRect();
        return {
          verdeckt: Math.round((topbar ? topbar.getBoundingClientRect().bottom : 0) - s.top),
          links: Math.round(c.left),
          rechts: Math.round(window.innerWidth - c.right)
        };
      })()
    JS

    assert_operator mass["verdeckt"], :<=, 0,
                    "die Topbar darf den Spine nicht anschneiden (#{mass['verdeckt']} px verdeckt)"
    assert_equal 0, mass["links"],  "der Stapel sitzt bündig an der linken Kante"
    assert_equal 0, mass["rechts"], "und an der rechten"
  end
end
