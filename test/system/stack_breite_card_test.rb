require "application_system_test_case"

# #1487 (Hans): „Die äußerst rechte Card wird beim Card-Scrollen nach links
# nicht komplett nach rechts ausgeblendet, sondern ein Streifen des
# Inhaltsbereiches bleibt rechts neben dem Spine stehen. Die Spines der
# folgenden Cards verschwinden dann hinter dieser rechten Card."
#
# Dahinter stecken ZWEI Fehler, die sich gegenseitig verdeckt haben.
#
# 1. Die Sticky-Rechnung merkt sich die Breite jeder Card
#    (`right = Stapel - Breite`). `.stack-card` hat aber eine
#    220ms-Transition auf `width` (#224). Wer direkt nach dem Setzen misst,
#    bekommt die ALTE Breite — die Card dockt dann um die Differenz zu weit
#    links an, und weil sie den hoechsten z-Index hat, bleibt ihr Rest als
#    Streifen stehen. Live: auf 1126px gezogen, gemessen 576px, 551px
#    Streifen. Dagegen der Breiten-Beobachter im Controller.
#
# 2. Erst mit der RICHTIGEN Breite kam der zweite Fehler zum Vorschein:
#    Die Klemmung aus #281 („die letzte Card soll ganz ins Viewport
#    passen") wurde bei einer uebergrossen Card zu einer Klemmung ganz
#    nach links (`Math.max(0, …)`) — Plaetze [0,4,8,…,24,0], also alle
#    anderen Spines unter der obersten Card. Dagegen die Aenderung in
#    lib/blade_stack_sticky.js.
#
# Deshalb prueft jeder Test genau einen der beiden: Test 1 faellt um, wenn
# nur der Beobachter da ist, Test 2, wenn keiner von beiden da ist.
class StackBreiteCardTest < ApplicationSystemTestCase
  ANZAHL = 8

  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update])
    grant(@hans, "Task", %w[read])

    @tmp_base = Pathname.new(Dir.mktmpdir("miolim-breit-"))
    @original_base = FileProxy::BASE_PATH
    FileProxy.send(:remove_const, :BASE_PATH)
    FileProxy.const_set(:BASE_PATH, @tmp_base)
    FileUtils.mkdir_p(@tmp_base.join("knowledge/notes"))

    @items = (1..ANZAHL).map do |i|
      uuid = SecureRandom.uuid
      rel  = "knowledge/notes/k#{i}.md"
      File.write(@tmp_base.join(rel), "---\nid: #{uuid}\ntype: note\n---\n\n# K#{i}\n\nInhalt #{i}.\n")
      KnowledgeItem.create!(uuid: uuid, title: "Karte #{i}", item_type: "note",
                            creator: @hans, file_path: rel, content_hash: "h#{i}")
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

  # Letzte Card breiter ziehen als der Arbeitsbereich — das macht der
  # Resize-Griff auch, er laesst bis `innerWidth - 80` zu und merkt sich
  # die Breite je Card-Art.
  def stack_mit_breiter_letzter
    page.driver.resize_window(1000, 700)
    visit "/knowledge_items?stack=#{@items.map(&:uuid).join(',')}"
    assert_selector "article.stack-card", minimum: ANZAHL, wait: 30
    page.execute_script(<<~JS)
      const c = document.getElementById("blade_stack_container");
      const cards = c.querySelectorAll(".stack-card");
      const letzte = cards[cards.length - 1];
      letzte.style.width = (c.clientWidth + 200) + "px";
      letzte.style.maxWidth = "none";
    JS
    # Bewusst OHNE restickify von aussen: Genau so aendert der Breiten-Griff
    # die Breite, und genau darum geht es — das Layout muss von selbst
    # nachziehen, wenn die 220ms-Transition durch ist. Wer hier haendisch
    # nachrechnen laesst, prueft die Rechnung und nicht den Ausloeser.
    sleep 0.6
  end

  test "die uebergrosse letzte Card deckt die Spines der anderen nicht zu" do
    stack_mit_breiter_letzter

    lefts = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll("#blade_stack_container .stack-card"))
           .map(k => Math.round(parseFloat(k.style.left) || 0))
    JS

    # Aufsteigend heisst: Jede Card hat ihren Platz LINKS von der naechsten.
    # Vorher stand die letzte auf 0 und lag damit unter allen anderen —
    # als oberste Card deckte sie deren Spines zu.
    aufsteigend = lefts.each_cons(2).all? { |a, b| b >= a }
    assert aufsteigend, "Pin-Plaetze muessen aufsteigend sein, sind #{lefts.inspect}"
    assert_operator lefts.last, :>=, lefts[-2],
                    "die letzte Card darf nicht links ihrer Vorgaengerin einrasten"
  end

  test "beim Wegscrollen nach links bleibt von ihr nur der Spine stehen" do
    stack_mit_breiter_letzter

    mass = page.evaluate_script(<<~JS)
      (() => {
        const c = document.getElementById("blade_stack_container");
        c.scrollLeft = 0;
        const cr = c.getBoundingClientRect();
        const cards = Array.from(c.querySelectorAll(".stack-card"));
        const letzte = cards[cards.length - 1];
        return {
          sichtbar: Math.round(cr.right - letzte.getBoundingClientRect().left),
          spine:    Math.round(letzte.querySelector(".stack-spine").getBoundingClientRect().width)
        };
      })()
    JS

    # „Nur noch der Spine" — ein Pixel Rahmen darf sein, ein Streifen
    # Inhaltsbereich nicht.
    assert_in_delta mass["spine"], mass["sichtbar"], 2,
                    "sichtbar #{mass['sichtbar']}px, Spine #{mass['spine']}px — " \
                    "der Rest waere der Streifen aus Hans' Meldung"
  end
end
