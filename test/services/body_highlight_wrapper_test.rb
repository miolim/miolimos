require "test_helper"

# #378 (Hans, 2026-05-26): Tests fuer BodyHighlightWrapper.
# Service aus #365 Phase 3 — wraps Absatz oder Selektion in
# `==color|text==`-Highlight, persistent im KI-Body-File.
class BodyHighlightWrapperTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
  end

  def create_note(content)
    FileProxy.create(
      actor: @hans, title: "Test", item_type: :note, content: content
    )
  end

  def body_of(item)
    FileProxy.read_body(actor: @hans, knowledge_item: item)
  end

  test "wraps whole block by block-N anchor" do
    with_isolated_miolimos_base do
      item = create_note("Erster Absatz.\n\nZweiter Absatz.\n")
      BodyHighlightWrapper.call(item: item, actor: @hans,
        anchor: "block-2", color: "gelb")
      body = body_of(item)
      assert_match(/==gelb\|Zweiter Absatz\.==/, body)
      assert_no_match(/==gelb\|Erster/, body)
    end
  end

  # #684 (Hans, 2026-06-13): Block-Nummerierungs-Drift zwischen gerenderter
  # DOM und Source (z.B. ein <hr> ohne block-id) ließ den Anker-Block die
  # Selektion verfehlen → "Selektion im Block nicht gefunden". Fallback:
  # den Block per Inhalt finden.
  test "Substring-Wrap findet den Block per Inhalt, wenn der Anker-Block (Drift) ihn nicht enthält" do
    with_isolated_miolimos_base do
      item = create_note("Erster Absatz.\n\nZweiter Absatz mit Zieltext.\n")
      # Anker zeigt (durch Drift) auf block-1, die Selektion liegt in block-2
      BodyHighlightWrapper.call(item: item, actor: @hans,
        anchor: "block-1", color: "gelb", selected_text: "Zieltext")
      body = body_of(item)
      assert_match(/==gelb\|Zieltext==/, body)
      assert_no_match(/==gelb\|Erster/, body)
    end
  end

  test "Substring-Wrap bevorzugt den Anker-Block bei mehrdeutigem Text" do
    with_isolated_miolimos_base do
      item = create_note("Wort hier.\n\nWort dort.\n")
      BodyHighlightWrapper.call(item: item, actor: @hans,
        anchor: "block-2", color: "gelb", selected_text: "Wort")
      body = body_of(item)
      assert_match(/Wort hier\./, body)                       # block-1 unangetastet
      assert_match(/==gelb\|Wort==\^[0-9a-f]{8} dort\./, body) # block-2 gewrappt
    end
  end

  # #475 (Hans, 2026-06-02): ein nachgestellter Block-Anker darf NICHT
  # sichtbar im Highlight landen — er wird rausgezogen + wiederverwendet.
  test "wrap_whole_block zieht nachgestellten Block-Anker raus und nutzt ihn als Anker" do
    with_isolated_miolimos_base do
      item = create_note("Ein Satz. ^abc123\n")
      BodyHighlightWrapper.call(item: item, actor: @hans, anchor: "block-1", color: "lila")
      body = body_of(item)
      assert_match(/==lila\|Ein Satz\.==\^abc123/, body)
      refute_includes body, "Satz. ^abc123=="   # Anker nicht IM Wrap
    end
  end

  # #475: Re-Color heilt einen Block, dessen Anker faelschlich IM Wrap
  # steckt (Hans-Report): Highlight-Anker behalten, Stray entfernen.
  test "Re-Color heilt Anker-im-Wrap" do
    with_isolated_miolimos_base do
      item = create_note("==lila|Text ^abc123==^14b542af\n")
      BodyHighlightWrapper.call(item: item, actor: @hans, anchor: "block-1", color: "gruen")
      body = body_of(item)
      assert_match(/==gruen\|Text==\^14b542af/, body)
      refute_includes body, "Text ^abc123"
    end
  end

  # #475: Unwrap behaelt den Block-Anker als nackten Trailing-Anker.
  test "Unwrap behaelt den Block-Anker" do
    with_isolated_miolimos_base do
      item = create_note("==lila|Text==^abc123\n")
      BodyHighlightWrapper.call(item: item, actor: @hans, anchor: "block-1", color: "keine")
      body = body_of(item)
      refute_includes body, "==lila"
      assert_includes body, "Text ^abc123"
    end
  end

  test "wraps substring inside block via selected_text" do
    with_isolated_miolimos_base do
      item = create_note("Ein wichtiger Satz.\n")
      BodyHighlightWrapper.call(item: item, actor: @hans,
        anchor: "block-1", color: "rot", selected_text: "wichtiger")
      body = body_of(item)
      # #387 Phase A: Wrap traegt jetzt einen 8-Hex-Anker am Ende.
      assert_match(/Ein ==rot\|wichtiger==\^[a-f0-9]{8} Satz\./, body)
    end
  end

  # #469 (Hans, 2026-06-02): result_anchor liefert den gesetzten Anker —
  # damit das Selektions-Menue praezise darauf verlinken/kommentieren kann.
  test "result_anchor liefert den beim Substring-Wrap gesetzten Anker" do
    with_isolated_miolimos_base do
      item = create_note("Ein wichtiger Satz.\n")
      wrapper = BodyHighlightWrapper.new(item: item, actor: @hans,
        anchor: "block-1", color: "gelb", selected_text: "wichtiger")
      wrapper.call
      assert_match(/\A[a-f0-9]{8}\z/, wrapper.result_anchor.to_s)
      assert_match(/==gelb\|wichtiger==\^#{wrapper.result_anchor}/, body_of(item))
    end
  end

  # #492 (Hans, 2026-06-03): Selektion ueberspannt Inline-Markup. Die DOM-
  # Auswahl (sel.toString()) enthaelt KEINE Marker — die Source schon. Frueher
  # warf das „Selektion im Block nicht gefunden"; jetzt wird die passende
  # Quell-Span markup-tolerant gefunden und balanciert gewrappt.
  test "Substring-Wrap toleriert uebersprungenes Inline-Markup (fett)" do
    with_isolated_miolimos_base do
      item = create_note("Sie stimmt als **Grobachse**, aber nicht ganz.\n")
      BodyHighlightWrapper.call(item: item, actor: @hans,
        anchor: "block-1", color: "gelb", selected_text: "stimmt als Grobachse")
      body = body_of(item)
      # Schliessendes ** wird mit-eingeschlossen -> Markdown bleibt gueltig.
      assert_match(/==gelb\|stimmt als \*\*Grobachse\*\*==\^[a-f0-9]{8}/, body)
    end
  end

  # #751 (Hans, 2026-06-21): Eine über mehrere eingerückte Fortsetzungs-
  # zeilen (Listenpunkt/Absatz) gezogene Selektion kommt aus dem DOM OHNE
  # die Quell-Einrückung ("…is\ninterchangeable…" statt "…is\n   inter…").
  # Exakte/markup-tolerante Suche scheiterte daran → "Selektion im Block
  # nicht gefunden". Jetzt whitespace-tolerant: jeder Whitespace-Run matcht.
  test "Substring-Wrap toleriert Quell-Einrueckung einer mehrzeiligen Selektion" do
    with_isolated_miolimos_base do
      item = create_note("3. Erster Teil des Punktes und\n   zweite eingerueckte Zeile und\n   dritte eingerueckte Zeile.\n")
      BodyHighlightWrapper.call(item: item, actor: @hans,
        anchor: "block-1", color: "gruen",
        selected_text: "Erster Teil des Punktes und\nzweite eingerueckte Zeile und\ndritte eingerueckte Zeile.")
      body = body_of(item)
      # Quell-Einrückung bleibt INNERHALB des Wraps erhalten, Markdown gueltig.
      assert_match(/==gruen\|Erster Teil des Punktes und\n   zweite eingerueckte Zeile und\n   dritte eingerueckte Zeile\.==\^[a-f0-9]{8}/, body)
      # Listen-Marker bleibt ausserhalb.
      assert_match(/\A3\. ==gruen\|/, body)
    end
  end

  test "Substring-Wrap eines fett-inneren Wortes wrappt INNERHALB der **" do
    with_isolated_miolimos_base do
      item = create_note("Sie stimmt als **Grobachse**, aber nicht ganz.\n")
      BodyHighlightWrapper.call(item: item, actor: @hans,
        anchor: "block-1", color: "gelb", selected_text: "Grobachse")
      body = body_of(item)
      # ** bleiben aussen, Highlight innen -> balanciert.
      assert_match(/\*\*==gelb\|Grobachse==\^[a-f0-9]{8}\*\*/, body)
    end
  end

  # #492 v2 (Hans, 2026-06-03): Selektion ueberspannt Inline-Code mit
  # intraword-Underscore (`anchor_id`). Frueher wurde `_` faelschlich als
  # Emphasis gestrippt -> „anchorid" != needle -> Fehler. Jetzt bleibt
  # Code-Inhalt + intraword-`_` wortgetreu.
  test "Substring-Wrap toleriert Inline-Code mit Underscore" do
    with_isolated_miolimos_base do
      item = create_note("Jede Relation hat eine eigene `anchor_id` (6-stellig) im Text.\n")
      BodyHighlightWrapper.call(item: item, actor: @hans,
        anchor: "block-1", color: "gelb",
        selected_text: "eine eigene anchor_id (6-stellig)")
      body = body_of(item)
      assert_match(/==gelb\|eine eigene `anchor_id` \(6-stellig\)==\^[a-f0-9]{8}/, body)
    end
  end

  # intraword-`_` ausserhalb von Code (z.B. ein Bezeichner im Fliesstext)
  # darf ebenfalls nicht als Emphasis fehlinterpretiert werden.
  test "Substring-Wrap behandelt intraword-Underscore als literal" do
    with_isolated_miolimos_base do
      item = create_note("Die Spalte parent_id_int referenziert die Task.\n")
      BodyHighlightWrapper.call(item: item, actor: @hans,
        anchor: "block-1", color: "gelb", selected_text: "Spalte parent_id_int referenziert")
      body = body_of(item)
      assert_match(/==gelb\|Spalte parent_id_int referenziert==\^[a-f0-9]{8}/, body)
    end
  end

  # #617 (Hans): Selektion ueberlappt die GRENZE eines bestehenden
  # Highlights (beginnt davor / endet dahinter) — frueher "Selektion im
  # Block nicht gefunden". Jetzt: geschnittene Wraps abstreifen, Anker
  # wiederverwenden, frisch wrappen.
  test "Substring-Wrap ueber den ANFANG eines bestehenden Highlights hinweg" do
    with_isolated_miolimos_base do
      item = create_note("Vorlauf Satz eins. ==rot|Markierter Kern==^aaaa1111 Nachlauf.\n")
      BodyHighlightWrapper.call(item: item, actor: @hans,
        anchor: "block-1", color: "blau", selected_text: "Satz eins. Markierter")
      body = body_of(item)
      assert_includes body, "==blau|Satz eins. Markierter==^aaaa1111"
      refute_includes body, "==rot|"
      assert_includes body, "Kern Nachlauf."   # Rest des alten Wraps entwrappt
    end
  end

  test "Substring-Wrap ueber das ENDE eines Highlights hinweg (Hans-Fall #617)" do
    with_isolated_miolimos_base do
      # Highlight endet am Blockende, dahinter nackter Block-Anker.
      item = create_note("Anfang frei. ==rot|Reservierte Schlusspassage.==^aaaa1111 ^bbb222\n")
      BodyHighlightWrapper.call(item: item, actor: @hans,
        anchor: "bbb222", color: "gelb", selected_text: "frei. Reservierte Schlusspassage.")
      body = body_of(item)
      assert_includes body, "==gelb|frei. Reservierte Schlusspassage.==^aaaa1111"
      refute_includes body, "==rot|"
      assert_includes body, "^bbb222"          # Block-Anker bleibt erhalten
    end
  end

  test "Substring-Wrap ueber ZWEI bestehende Highlights hinweg" do
    with_isolated_miolimos_base do
      item = create_note("A ==rot|eins==^aaaa1111 mitte ==blau|zwei==^cccc3333 Ende.\n")
      BodyHighlightWrapper.call(item: item, actor: @hans,
        anchor: "block-1", color: "lila", selected_text: "eins mitte zwei")
      body = body_of(item)
      assert_includes body, "==lila|eins mitte zwei==^aaaa1111"  # erster Anker gewinnt
      refute_includes body, "==rot|"
      refute_includes body, "==blau|"
    end
  end

  # #617 v2: Renderer cappte bei 800 Zeichen, der Wrapper nicht — ein
  # Block-Highlight auf lange Transkript-Absätze erzeugte unrenderbaren
  # ==rot|…-Klartext. Jetzt: Limit überall 4000, Wrapper lehnt darüber ab.
  test "langer Block (>800) wrappt und RENDERT als mark (#617)" do
    with_isolated_miolimos_base do
      long = "Wort " * 250   # ~1250 Zeichen
      item = create_note("#{long.strip}\n")
      BodyHighlightWrapper.call(item: item, actor: @hans,
        anchor: "block-1", color: "rot", selected_text: nil)
      html = KnowledgeMarkdown.render(body_of(item))
      assert_includes html, "<mark", "langer Wrap muss als mark rendern"
      refute_includes html, "==rot|", "kein Klartext-Markup im Render"
    end
  end

  test "ueberlanger Block (>4000) wird sauber abgelehnt" do
    with_isolated_miolimos_base do
      item = create_note("#{("Wort " * 900).strip}\n")
      err = assert_raises(BodyHighlightWrapper::Error) do
        BodyHighlightWrapper.call(item: item, actor: @hans,
          anchor: "block-1", color: "rot", selected_text: nil)
      end
      assert_match(/zu lang/, err.message)
    end
  end

  test "Substring-Wrap wirft weiterhin bei echt fehlendem Text" do
    with_isolated_miolimos_base do
      item = create_note("Ein ganz normaler Satz.\n")
      assert_raises(BodyHighlightWrapper::Error) do
        BodyHighlightWrapper.call(item: item, actor: @hans,
          anchor: "block-1", color: "gelb", selected_text: "kommt nicht vor")
      end
    end
  end

  test "result_anchor bleibt nil beim Unwrap (keine)" do
    with_isolated_miolimos_base do
      item = create_note("Ein ==gelb|wichtiger==^a1b2c3d4 Satz.\n")
      wrapper = BodyHighlightWrapper.new(item: item, actor: @hans,
        anchor: "block-1", color: "keine", selected_text: "wichtiger")
      wrapper.call
      assert_nil wrapper.result_anchor
    end
  end

  test "unwrap keine removes existing wrap on the block" do
    with_isolated_miolimos_base do
      item = create_note("Schon ==gelb|hervorgehobener Absatz==.\n")
      BodyHighlightWrapper.call(item: item, actor: @hans,
        anchor: "block-1", color: "keine")
      body = body_of(item)
      assert_no_match(/==gelb\|/, body)
      assert_match(/Schon hervorgehobener Absatz/, body)
    end
  end

  test "double-apply replaces color instead of double-wrapping" do
    with_isolated_miolimos_base do
      item = create_note("Ein Absatz.\n")
      BodyHighlightWrapper.call(item: item, actor: @hans,
        anchor: "block-1", color: "gelb")
      BodyHighlightWrapper.call(item: item, actor: @hans,
        anchor: "block-1", color: "rot")
      body = body_of(item)
      assert_match(/==rot\|Ein Absatz\.==/, body)
      assert_no_match(/==gelb\|/, body)
    end
  end

  # #449 (Hans, 2026-06-01): Listen-Marker bleibt beim Whole-Block-Wrap
  # vor dem `==…==`, damit der Renderer die Zeile weiter als Listenpunkt
  # erkennt (sonst wurde aus „- foo" ein Absatz mit literalem „-").
  test "keeps list bullet marker outside the wrap" do
    with_isolated_miolimos_base do
      item = create_note("- Erster Punkt\n- Zweiter Punkt\n")
      BodyHighlightWrapper.call(item: item, actor: @hans,
        anchor: "block-1", color: "gelb")
      body = body_of(item)
      assert_match(/^- ==gelb\|Erster Punkt==\^[a-f0-9]{8}$/, body)
      assert_no_match(/==gelb\|- /, body)
    end
  end

  test "keeps ordered-list and indentation markers outside the wrap" do
    with_isolated_miolimos_base do
      item = create_note("  1. Eingerueckt\n")
      BodyHighlightWrapper.call(item: item, actor: @hans,
        anchor: "block-1", color: "blau")
      body = body_of(item)
      assert_match(/^  1\. ==blau\|Eingerueckt==\^[a-f0-9]{8}$/, body)
    end
  end

  test "keeps heading and blockquote markers outside the wrap" do
    with_isolated_miolimos_base do
      heading = create_note("## Titel\n")
      BodyHighlightWrapper.call(item: heading, actor: @hans,
        anchor: "block-1", color: "gruen")
      assert_match(/^## ==gruen\|Titel==\^[a-f0-9]{8}$/, body_of(heading))

      quote = create_note("> Zitat\n")
      BodyHighlightWrapper.call(item: quote, actor: @hans,
        anchor: "block-1", color: "rot")
      assert_match(/^> ==rot\|Zitat==\^[a-f0-9]{8}$/, body_of(quote))
    end
  end

  # Re-Color eines bereits (alt-fehlerhaft) gewrappten Listen-Items
  # heilt den Marker beim naechsten Wrap wieder heraus.
  test "re-color self-heals a list item with marker inside the old wrap" do
    with_isolated_miolimos_base do
      item = create_note("==gelb|- Alt verdrahtet==^abcdef12\n")
      BodyHighlightWrapper.call(item: item, actor: @hans,
        anchor: "block-1", color: "rot")
      body = body_of(item)
      assert_match(/^- ==rot\|Alt verdrahtet==\^abcdef12$/, body)
    end
  end

  test "raises on invalid color" do
    with_isolated_miolimos_base do
      item = create_note("Etwas.\n")
      assert_raises(BodyHighlightWrapper::Error) do
        BodyHighlightWrapper.call(item: item, actor: @hans,
          anchor: "block-1", color: "neon")
      end
    end
  end

  test "raises when block-anchor is not found" do
    with_isolated_miolimos_base do
      item = create_note("Etwas.\n")
      assert_raises(BodyHighlightWrapper::Error) do
        BodyHighlightWrapper.call(item: item, actor: @hans,
          anchor: "block-99", color: "gelb")
      end
    end
  end

  test "raises when selected_text not present in the block" do
    with_isolated_miolimos_base do
      item = create_note("Ein Absatz.\n")
      assert_raises(BodyHighlightWrapper::Error) do
        BodyHighlightWrapper.call(item: item, actor: @hans,
          anchor: "block-1", color: "blau", selected_text: "nicht da")
      end
    end
  end
end
