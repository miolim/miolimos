require "application_system_test_case"

# Uebernahme aus immoos (Hinweis von immoos_builder, 2026-09-01): Beim
# Anhaengen einer Card sprang der Stapel ans RECHNERISCHE ENDE statt zur
# neuen Card.
#
# Solange dieses Ende rechts der aktuellen Position liegt, ist beides
# dasselbe und nichts faellt auf. Passen die Cards nach dem Anhaengen aber
# zusammen in den Container, ist der Wert KLEINER als die aktuelle Position —
# der Stapel springt nach links zurueck und klappt dabei die weggescrollten
# Spines wieder auf. Man scrollt eine Liste auf ihren Ruecken weg, klickt in
# der offenen Card auf einen Verweis, und die Liste steht wieder da.
#
# Genau diese Bedingung ist die Falle beim Nachstellen: Bei zu schmalem
# Fenster ist der alte Code zufaellig richtig.
#
# Gemessen wird der sichtbare Streifen als ABSTAND ZWEIER CARD-KANTEN, nicht
# ueber Klassennamen: So haengt der Test nicht daran, wie eine
# eingeklappte Card gerade heisst.
class StackAnhaengenHaeltPositionTest < ApplicationSystemTestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update])
    grant(@hans, "Task", %w[read])

    @tmp_base = Pathname.new(Dir.mktmpdir("miolim-anhaengen-"))
    @original_base = FileProxy::BASE_PATH
    FileProxy.send(:remove_const, :BASE_PATH)
    FileProxy.const_set(:BASE_PATH, @tmp_base)
    FileUtils.mkdir_p(@tmp_base.join("knowledge/notes"))

    @items = %w[alpha beta gamma delta].map do |name|
      uuid = SecureRandom.uuid
      rel  = "knowledge/notes/#{name}.md"
      File.write(@tmp_base.join(rel), "---\nid: #{uuid}\ntype: note\n---\n\n# #{name}\n\nInhalt.\n")
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

  MASS = <<~JS.freeze
    (() => {
      const c = document.getElementById("blade_stack_container");
      const k = Array.from(c.querySelectorAll(".stack-card")).map(x => x.getBoundingClientRect());
      return {
        scroll: Math.round(c.scrollLeft),
        // Der sichtbare Streifen der ERSTEN Card ist der Abstand zur zweiten.
        streifen: k.length > 1 ? Math.round(k[1].left - k[0].left) : null,
        cards: k.length
      };
    })()
  JS

  def messen = page.evaluate_script(MASS)

  test "eine angehaengte Card verschiebt den Stapel nicht zurueck" do
    # Breit genug, dass die Cards nach dem Anhaengen zusammen hineinpassen —
    # nur dann zeigt sich der Fehler. Unter 768px greift ausserdem die
    # Mobil-Ansicht ganz ohne Spines.
    page.driver.resize_window(1600, 900)
    visit "/knowledge_items?stack=#{@items[0].uuid},#{@items[1].uuid}"
    assert_selector "article.stack-card[data-uuid='#{@items[1].uuid}']", wait: 10

    # Ganz nach rechts scrollen — in den Freiraum hinter dem rechnerischen
    # Content-Ende (#1091 v4: der Stapel hat dort einen stehenden Spacer).
    # NUR DORT liegt das rechnerische Ende LINKS der aktuellen Position, und
    # nur dann springt der alte Code zurueck. Das ist die Bedingung, an der
    # man beim Nachstellen dreimal vorbeilaeuft.
    page.execute_script(<<~JS)
      const c = document.getElementById("blade_stack_container");
      c.scrollLeft = c.scrollWidth;
    JS
    sleep 0.5
    vorher = messen
    assert_operator vorher["scroll"], :>, 0, "der Stapel muss verschoben sein, sonst misst der Test nichts"

    # Vorbedingung ausdruecklich pruefen: Liegt das rechnerische Ende wirklich
    # LINKS von uns? Sonst ist der alte Code zufaellig richtig und der Test
    # gruen, ohne etwas gezeigt zu haben.
    lage = page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('[data-controller~="blade-stack"]');
        const ctl = (window.Stimulus || window.application)
                      .getControllerForElementAndIdentifier(el, "blade-stack");
        const c = document.getElementById("blade_stack_container");
        return { ende: Math.round(ctl._naturalEndScroll()), jetzt: Math.round(c.scrollLeft) };
      })()
    JS
    assert_operator lage["ende"], :<, lage["jetzt"],
                    "Vorbedingung: das rechnerische Ende (#{lage['ende']}) muss links der " \
                    "aktuellen Position (#{lage['jetzt']}) liegen — sonst zeigt sich der Fehler nicht"

    # Dritte Card anhaengen — ueber `appendCard`, den Weg, den ein Verweis
    # ohne Listen-Herkunft nimmt. Das globale Append-Ereignis waere hier die
    # falsche Nachstellung: Es laeuft ueber `_appendBladeAtUrl`, und der Pfad
    # war schon richtig. Beim ersten Anlauf war mein Test deshalb gruen,
    # ohne die fragliche Zeile ueberhaupt zu beruehren.
    page.execute_script(<<~JS)
      const el = document.querySelector('[data-controller~="blade-stack"]');
      (window.Stimulus || window.application)
        .getControllerForElementAndIdentifier(el, "blade-stack")
        .appendCard("#{@items[2].uuid}");
    JS
    assert_selector "article.stack-card[data-uuid='#{@items[2].uuid}']", wait: 10
    sleep 0.8

    nachher = messen
    assert_equal 3, nachher["cards"], "die dritte Card haengt dran"
    assert_in_delta vorher["scroll"], nachher["scroll"], 2,
                    "der Stapel darf nicht zurueckspringen (#{vorher['scroll']} → #{nachher['scroll']})"
    assert_in_delta vorher["streifen"], nachher["streifen"], 2,
                    "und die weggescrollte Card darf nicht wieder aufklappen " \
                    "(#{vorher['streifen']}px → #{nachher['streifen']}px)"
  end

  # #1501 R2 (gemeldet von immoos_builder, belegt mit Hans' Browser-Zahlen aus
  # dem Fork): der Fall, den die beiden Tests oben NICHT treffen. Sie haengen
  # an — rechts der aufrufenden Card steht nichts, also gibt es nichts zu
  # entfernen und der Ablauf nimmt den Anhaenge-Pfad. Steht rechts dagegen eine
  # Card, wird sie ERSETZT: Sie verschwand bisher VOR dem Laden der neuen, der
  # End-Freiraum schrumpfte, und der Browser kappte scrollLeft.
  test "eine ersetzte Card laesst den Stapel stehen" do
    page.driver.resize_window(1600, 900)
    visit "/knowledge_items?stack=#{@items[0].uuid},#{@items[1].uuid}"
    assert_selector "article.stack-card[data-uuid='#{@items[1].uuid}']", wait: 10

    # Dritte Card anhaengen — sie ist gleich die, die ersetzt wird.
    page.execute_script(<<~JS)
      const el = document.querySelector('[data-controller~="blade-stack"]');
      (window.Stimulus || window.application)
        .getControllerForElementAndIdentifier(el, "blade-stack")
        .appendCard("#{@items[2].uuid}");
    JS
    assert_selector "article.stack-card[data-uuid='#{@items[2].uuid}']", wait: 10

    # Nach rechts scrollen, damit ueberhaupt eine Position da ist, die
    # verlorengehen kann — und die erste Card weggescrollt ist.
    page.execute_script(<<~JS)
      const c = document.getElementById("blade_stack_container");
      c.scrollLeft = c.scrollWidth;
    JS
    sleep 0.5
    vorher = messen
    assert_operator vorher["scroll"], :>, 0,
                    "Vorbedingung: der Stapel muss verschoben sein, sonst misst der Test nichts"

    # Vorbedingung des Fehlers ausdruecklich pruefen: Faellt die maximale
    # Scrollposition OHNE die zu ersetzende Card unter die aktuelle? Nur dann
    # kappt der Browser, und nur dann zeigt der alte Code den Fehler.
    ohne = page.evaluate_script(<<~JS)
      (() => {
        const c = document.getElementById("blade_stack_container");
        const k = c.querySelector('.stack-card[data-uuid="#{@items[2].uuid}"]');
        return Math.round(c.scrollWidth - k.getBoundingClientRect().width - c.clientWidth);
      })()
    JS
    assert_operator ohne, :<, vorher["scroll"],
                    "Vorbedingung: ohne die ersetzte Card (#{ohne}) muss das Maximum unter " \
                    "der aktuellen Position (#{vorher['scroll']}) liegen — sonst kappt nichts"

    # Klick in der ZWEITEN Card; rechts von ihr steht die dritte, die wird
    # ersetzt (die Regel aus #1509 fuer den schlichten Klick).
    page.execute_script(<<~JS)
      window.dispatchEvent(new CustomEvent("blade-stack:append", { detail: {
        kind: "ki", id: "#{@items[3].uuid}",
        quelleId: "stack_card_#{@items[1].uuid}", oeffnen: "ersetzen" } }))
    JS
    assert_selector "article.stack-card[data-uuid='#{@items[3].uuid}']", wait: 15
    assert_no_selector "article.stack-card[data-uuid='#{@items[2].uuid}']", wait: 10
    sleep 0.8

    nachher = messen
    assert_equal 3, nachher["cards"], "ersetzt, nicht angehaengt"
    assert_in_delta vorher["scroll"], nachher["scroll"], 2,
                    "der Stapel darf beim Ersetzen nicht wegspringen " \
                    "(#{vorher['scroll']} → #{nachher['scroll']})"
    assert_in_delta vorher["streifen"], nachher["streifen"], 2,
                    "und die weggescrollte Card darf nicht wieder aufklappen " \
                    "(#{vorher['streifen']}px → #{nachher['streifen']}px)"
  end

  # Gegenprobe: „nicht bewegen" darf nicht heimlich zu „neue Card liegt
  # ausserhalb des Bildes" werden.
  test "die neue Card steht danach im Bild" do
    page.driver.resize_window(1600, 900)
    visit "/knowledge_items?stack=#{@items[0].uuid}"
    assert_selector "article.stack-card", wait: 10

    page.execute_script(<<~JS)
      const el = document.querySelector('[data-controller~="blade-stack"]');
      (window.Stimulus || window.application)
        .getControllerForElementAndIdentifier(el, "blade-stack")
        .appendCard("#{@items[1].uuid}");
    JS
    assert_selector "article.stack-card[data-uuid='#{@items[1].uuid}']", wait: 10
    sleep 0.8

    sichtbar = page.evaluate_script(<<~JS)
      (() => {
        const c = document.getElementById("blade_stack_container");
        const k = c.querySelector('.stack-card[data-uuid="#{@items[1].uuid}"]');
        const cr = c.getBoundingClientRect(), r = k.getBoundingClientRect();
        return Math.round(Math.min(r.right, cr.right) - Math.max(r.left, cr.left));
      })()
    JS
    assert_operator sichtbar, :>, 100, "die neue Card muss sichtbar sein, nicht nur vorhanden"
  end
end
