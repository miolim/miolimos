require "application_system_test_case"

# #206 Phase 1: Smoke-Tests fuer paragraph_actions_controller.js.
# Der Controller haengt sich an `<div data-controller="paragraph-actions">`,
# scannt `<p>/<li>/<blockquote>` mit `id`-Attribut und reichert sie um
# eine Hover-Toolbar an. Wir bauen ein KI mit identifizierbaren Bloecken
# und pruefen die Stimulus-Aufhaengung + DOM-Reaktion.
class ParagraphActionsTest < ApplicationSystemTestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update])
    grant(@hans, "Topic", %w[read])
    grant(@hans, "Task", %w[read])

    # Capybara faehrt Puma in-process — daher reicht es, FileProxy::BASE_PATH
    # auf ein Tmp-Dir umzubiegen und dort eine Markdown-Datei zu schreiben.
    # KnowledgeMarkdown.render injiziert Block-IDs (block-1, block-2, ...),
    # auf die der Stimulus-Controller dann reagiert.
    @tmp_base = Pathname.new(Dir.mktmpdir("miolim-systest-"))
    @original_base = FileProxy::BASE_PATH
    FileProxy.send(:remove_const, :BASE_PATH)
    FileProxy.const_set(:BASE_PATH, @tmp_base)

    rel_path = "knowledge/notes/test-paragraph-actions.md"
    FileUtils.mkdir_p(@tmp_base.join("knowledge/notes"))
    File.write(@tmp_base.join(rel_path),
      "---\nid: probe\ntype: note\n---\n\n" \
      "Erster Absatz mit Inhalt.\n\nZweiter Absatz.\n\nDritter Absatz.\n")

    @item = KnowledgeItem.create!(
      uuid:         SecureRandom.uuid,
      title:        "Test-KI fuer Paragraph-Actions",
      item_type:    "note",
      creator:      @hans,
      file_path:    rel_path,
      content_hash: "h0",
      # #241/#564: DB ist Source of Truth — der Body MUSS in der Spalte
      # stehen, die Datei ist nur Export (der Test schrieb frueher nur die
      # Datei und lief seit dem Reader-Umbau gegen einen leeren Body).
      body:         "Erster Absatz mit Inhalt.\n\nZweiter Absatz.\n\nDritter Absatz.\n"
    )

    login_as(@hans)
  end

  teardown do
    if @original_base
      FileProxy.send(:remove_const, :BASE_PATH)
      FileProxy.const_set(:BASE_PATH, @original_base)
    end
    FileUtils.remove_entry(@tmp_base) if @tmp_base&.exist?
  end

  test "Detail-Seite haengt paragraph-actions Controller an die Markdown-Body" do
    visit knowledge_item_path(@item.uuid)
    # Direkte Body-Stelle: data-controller="...paragraph-actions"
    assert page.has_css?('[data-controller~="paragraph-actions"]'),
           "data-controller=paragraph-actions muss am Body-Container haengen"
    assert_equal @item.uuid,
                 find('[data-controller~="paragraph-actions"]')["data-paragraph-actions-uuid-value"]
  end

  test "Hover ueber Paragraphen blendet die Action-Toolbar ein" do
    visit knowledge_item_path(@item.uuid)
    # Stimulus haengt eine .para-actions-Toolbar an jeden p[id] an. Die
    # Toolbar ist per Default `opacity-0` (Tailwind), wird per group-hover
    # eingeblendet — Capybara braucht `visible: :all`, um sie zu sehen.
    assert page.has_css?(".para-actions", minimum: 1, visible: :all),
           "Mindestens eine para-actions-Toolbar muss eingehaengt sein"
    assert page.has_css?('.para-actions button[data-action="copy-link"]', visible: :all)
    assert page.has_css?('.para-actions button[data-action="copy-text"]', visible: :all)
    assert page.has_css?('.para-actions button[data-action="research"]', visible: :all)
    assert page.has_css?('.para-actions button[data-action="comment"]', visible: :all)
  end

  test "Paragraph-Bloecke kriegen para-anchorable und relative Klassen" do
    visit knowledge_item_path(@item.uuid)
    # Markdown-Renderer (KnowledgeMarkdown.inject_block_ids) gibt jedem
    # Absatz ein id=block-N; der Stimulus-Controller flaggt sie.
    blocks = page.all(".markdown-body p[id].para-anchorable", minimum: 1)
    assert_operator blocks.size, :>=, 1
  end

  # #208 Sicherheitsnetz: Backlinks-Popover. Wird vor dem Refactor
  # (Extraktion in lib/backlinks_popover.js) angelegt und muss danach
  # weiter gruen sein.
  test "openBacklinksPopover fetcht und rendert einen Popover mit Items" do
    visit knowledge_item_path(@item.uuid)
    # JSON-Endpoint stuben: window.fetch durch eine Lambda ersetzen,
    # die fuer den Backlinks-URL eine vorbereitete Antwort liefert.
    page.execute_script(<<~JS)
      window.__origFetch = window.fetch
      window.fetch = (url, opts) => {
        if (url.includes("/backlinks?")) {
          return Promise.resolve({
            ok: true,
            json: () => Promise.resolve({
              anchor: "block-1",
              items: [{ uuid: "11111111-1111-1111-1111-111111111111", title: "Quelle A", item_type: "note" }]
            })
          })
        }
        return window.__origFetch(url, opts)
      }

      // Action triggern: showBacklinks erwartet event.currentTarget.dataset.anchor
      const el = document.querySelector("[data-controller~='paragraph-actions']")
      const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, "paragraph-actions")
      const fakeLink = document.createElement("a")
      fakeLink.dataset.anchor = "block-1"
      document.body.appendChild(fakeLink)
      ctrl.showBacklinks({ preventDefault() {}, stopPropagation() {}, currentTarget: fakeLink })
    JS
    assert page.has_css?(".backlink-popover", visible: :all),
           "Popover muss nach showBacklinks im Body sein"
    assert page.has_text?("Quelle A"),
           "Popover muss die geladene Backlink-Quelle anzeigen"
  end

  test "openBacklinksPopover zeigt 'Keine Backlinks' wenn API leer ist" do
    visit knowledge_item_path(@item.uuid)
    page.execute_script(<<~JS)
      window.fetch = () => Promise.resolve({
        ok: true,
        json: () => Promise.resolve({ anchor: "x", items: [] })
      })
      const el = document.querySelector("[data-controller~='paragraph-actions']")
      const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, "paragraph-actions")
      const fakeLink = document.createElement("a")
      fakeLink.dataset.anchor = "x"
      document.body.appendChild(fakeLink)
      ctrl.showBacklinks({ preventDefault() {}, stopPropagation() {}, currentTarget: fakeLink })
    JS
    assert page.has_css?(".backlink-popover", visible: :all)
    assert page.has_text?("Keine Backlinks")
  end
end
