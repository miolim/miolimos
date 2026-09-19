require "test_helper"

# #1677 (aus immoOS #1658 übernommen; Hans dort): „Ich möchte nach und nach Hilfe-Cards ergänzen, die das
# Programm erläutern. … Oben ein Bereich, den der Nutzer selbst bearbeiten kann;
# unten der Bereich, der vom Programm geliefert wird."
class HilfeKarten1658Test < ActionDispatch::IntegrationTest
  setup do
    @admin = HumanActor.create!(name: "Hans", email: "hk-#{SecureRandom.hex(3)}@t.local",
                                password: "secretsecret", role: :admin)
    @mitarbeit = HumanActor.create!(name: "Mitarbeit", email: "hk2-#{SecureRandom.hex(3)}@t.local",
                                    password: "secretsecret", role: :member)
    [@admin, @mitarbeit].each { |a| grant(a, "KnowledgeItem", %w[read create update]) }
    grant(@admin, "Task", %w[read create update])
    grant(@mitarbeit, "Task", %w[read])
  end

  def anmelden(actor)
    post "/login", params: { email: actor.email, password: "secretsecret" }
  end

  # ── Die Card ─────────────────────────────────────────────────────────

  test "#1658: die Hilfe-Card zeigt beide Bereiche" do
    anmelden(@admin)
    get help_card_path(key: "task")
    assert_response :success
    assert_includes @response.body, I18n.t("hilfe.eigener_bereich")
    assert_includes @response.body, I18n.t("hilfe.programm_bereich")
    assert_includes @response.body, "stack_card_help:task"
  end

  test "#1658: ein unbekannter Schlüssel wird abgewiesen" do
    anmelden(@admin)
    get help_card_path(key: "task"), params: {}
    assert_response :success
    get "/help/BOESE!/card"
    assert_response :not_found
  end

  # ── Schreibrechte ────────────────────────────────────────────────────

  test "#1658: den oberen Bereich darf auch die Mitarbeit schreiben" do
    anmelden(@mitarbeit)
    patch help_path(key: "task"), params: { bereich: "user", text: "Bei uns gilt …" }
    assert_response :success
    assert_equal "Bei uns gilt …", HelpCard.find_by(key: "task").user_body
  end

  test "#1658: den unteren Bereich nur Administratoren" do
    anmelden(@mitarbeit)
    patch help_path(key: "task"), params: { bereich: "program", text: "So funktioniert es" }
    assert_response :forbidden
    assert_nil HelpCard.find_by(key: "task")

    anmelden(@admin)
    patch help_path(key: "task"), params: { bereich: "program", text: "So funktioniert es" }
    assert_response :success
    assert_equal "So funktioniert es", HelpCard.find_by(key: "task").program_body
  end

  test "#1658: die Mitarbeit LIEST den unteren Bereich" do
    HelpCard.create!(key: "task", program_body: "Erklärung für alle")
    anmelden(@mitarbeit)
    get help_card_path(key: "task")
    assert_includes @response.body, "Erklärung für alle"
  end

  # Eine Hilfe ohne Inhalt braucht keine Zeile — sonst sammelt die Tabelle
  # leere Einträge für jede Card, die jemand einmal aufgeklappt hat.
  test "#1658: leeren beider Bereiche entfernt den Eintrag wieder" do
    anmelden(@admin)
    patch help_path(key: "task"), params: { bereich: "user", text: "Notiz" }
    assert HelpCard.exists?(key: "task")

    patch help_path(key: "task"), params: { bereich: "user", text: "" }
    assert_not HelpCard.exists?(key: "task")
  end

  # ── Das Fragezeichen im Rücken ───────────────────────────────────────

  test "#1658: die Karte trägt das Fragezeichen, blass ohne Inhalt" do
    aufgabe = create_task(creator: @admin, title: "Musteraufgabe")
    anmelden(@admin)
    get "/tasks/#{aufgabe.id}/card"
    assert_response :success
    assert_includes @response.body, %(data-help-link-kind-value="help")
    assert_includes @response.body, %(data-help-link-id-value="task")
    assert_includes @response.body, I18n.t("hilfe.spine_leer")
  end

  # Hans: „damit man nicht ständig umsonst nach der Hilfe schaut."
  test "#1658: mit Inhalt sieht das Fragezeichen anders aus" do
    aufgabe = create_task(creator: @admin, title: "Musteraufgabe")
    HelpCard.create!(key: "task", program_body: "Erklärung")
    anmelden(@admin)
    get "/tasks/#{aufgabe.id}/card"
    assert_includes @response.body, I18n.t("hilfe.spine_vorhanden")
    assert_not_includes @response.body, I18n.t("hilfe.spine_leer")
  end

  # Auf der FOKUSSIERTEN Card faerbt eine alte Regel (#913) alle Spine-Inhalte
  # schwarz — und das ist die Card, auf die man schaut. Ohne diese Klasse waere
  # der Unterschied blass/blau genau dort unsichtbar, wo er gebraucht wird.
  test "#1658 R3: das Fragezeichen traegt die Ausnahme fuer den aktiven Ruecken" do
    aufgabe = create_task(creator: @admin, title: "Musteraufgabe")
    anmelden(@admin)
    get "/tasks/#{aufgabe.id}/card"
    assert_includes @response.body, "spine-hilfe-icon"
  end

  # Wer den Text schreibt, muss ihn auch lesen koennen — sonst sieht der
  # Verfasser seine eigene Erklaerung nie anders als im Schreibfeld.
  test "#1658: Administratoren sehen die Erklärung gesetzt UND bearbeitbar" do
    HelpCard.create!(key: "task", program_body: "Die **Aufgabe** ist die kleinste Einheit.")
    anmelden(@admin)
    get help_card_path(key: "task")
    assert_includes @response.body, "<strong>Aufgabe</strong>"
    assert_includes @response.body, I18n.t("hilfe.bearbeiten")
  end

  # ── Markdown (#1658 R2) ──────────────────────────────────────────────

  # Hans: „Könnte die Hilfe Markdown-Formatierungen erlauben? Dann könnte sie
  # noch etwas strukturierter dargestellt werden."
  test "#1658 R2: beide Bereiche werden als Markdown gesetzt" do
    HelpCard.create!(key: "task", user_body: "Unsere **Regel**",
                     program_body: "## Ebenen\n\n- Aufgabe\n- Thema")
    anmelden(@mitarbeit)
    get help_card_path(key: "task")
    assert_includes @response.body, "<strong>Regel</strong>"
    # Der Renderer haengt Absatz-IDs an (#465) — geprueft wird die Struktur.
    assert_match(%r{<h2[^>]*>Ebenen</h2>}, @response.body)
    assert_match(%r{<li[^>]*>Aufgabe</li>}, @response.body)
  end

  test "#1658 R2: der Hinweis auf Markdown steht am Schreibfeld" do
    anmelden(@mitarbeit)
    get help_card_path(key: "task")
    assert_includes @response.body, I18n.t("hilfe.markdown_hinweis")
  end

  # ── Stufe 2: Hilfe je Reiter ─────────────────────────────────────────

  test "#1658 S2: ein Reiter-Schlüssel ist eine eigene Hilfe" do
    anmelden(@admin)
    patch help_path(key: "ki.master_data"), params: { bereich: "program", text: "Zur Abrechnung" }
    assert_response :success
    assert_equal "Zur Abrechnung", HelpCard.find_by(key: "ki.master_data").program_body
    # Die allgemeine Hilfe bleibt davon unberührt.
    assert_nil HelpCard.find_by(key: "task")
  end

  test "#1658 S2: die Bezugszeile nennt den Reiter mit seinem Namen" do
    anmelden(@admin)
    get help_card_path(key: "ki.master_data")
    assert_includes @response.body, I18n.t("hilfe.reiter.ki.master_data")
  end

  # #1677: Im Fork hing der Reitername an dessen Immobilien-Schlüsseln. Upstream:
  # `hilfe.reiter.<art>.<reiter>` — und ohne Eintrag der lesbar gemachte
  # technische Name, damit ein Fork oder eine neue Karte nie „Reiter foo_bar" zeigt.
  test "#1658 R4: ein Reiter ohne eigenen Eintrag heisst nach seinem technischen Namen" do
    anmelden(@admin)
    get help_card_path(key: "ki.master_data")
    assert_includes @response.body, I18n.t("hilfe.reiter.ki.master_data")

    get help_card_path(key: "task.noch_unbekannt")
    assert_includes @response.body, "Noch unbekannt"
  end

  # Der Server weiß nicht, welcher Reiter offen ist — das Fragezeichen muss
  # trotzdem zeigen, dass es zu dieser Karte etwas gibt.
  test "#1658 S2: Text zu einem Reiter färbt das Fragezeichen der Karte" do
    aufgabe = create_task(creator: @admin, title: "Musteraufgabe")
    HelpCard.create!(key: "task.irgendein_reiter", program_body: "Zum Reiter")
    anmelden(@admin)
    get "/tasks/#{aufgabe.id}/card"
    assert_includes @response.body, I18n.t("hilfe.spine_vorhanden")
    assert_not_includes @response.body, I18n.t("hilfe.spine_leer")
  end

  # ── R3: Darstellung und Adresse ──────────────────────────────────────

  # Hans: „Überschriften scheinen nicht erkannt zu werden." Sie WURDEN erkannt,
  # sahen aber aus wie Fließtext: Die Card trug `prose`-Klassen, die es in
  # diesem Projekt nicht gibt (kein Typography-Plugin). Die hiesigen
  # Markdown-Stile heißen markdown-body — ohne sie setzt Tailwinds Preflight
  # Überschriften und Listen auf Normalgröße ohne Aufzählungszeichen zurück.
  test "#1658 R3: der gesetzte Text traegt die Markdown-Stile des Projekts" do
    HelpCard.create!(key: "task", program_body: "## Ebenen\n\n- Aufgabe")
    anmelden(@mitarbeit)
    get help_card_path(key: "task")
    assert_includes @response.body, "markdown-body"
    assert_not_includes @response.body, "prose prose-sm"
  end

  # Hans: „Der Link-kopieren-Button im Spine kopiert nur einen generischen
  # Link … Der sollte auf die konkrete Hilfe-Card verweisen."
  test "#1658 R3: der Kopier-Knopf traegt die Adresse dieser Hilfe" do
    anmelden(@admin)
    get help_card_path(key: "ki.master_data")
    kopiert = @response.body[/copy-clipboard-content-value="([^"]+)"/, 1]
    assert_includes kopiert.to_s, "/help/ki.master_data"
    assert_not_includes kopiert.to_s, "dashboard"
  end

  test "#1658 R3: die Adresse einer Hilfe oeffnet sie im Stapel" do
    anmelden(@admin)
    get help_seite_path(key: "ki.master_data")
    assert_redirected_to dashboard_path(stack: "help:ki.master_data")
  end

  test "#1658 R3: ein unbrauchbarer Schluessel hat auch keine Adresse" do
    anmelden(@admin)
    get "/help/BOESE!"
    assert_response :not_found
  end

  # Ohne den help-Zweig im BladeStackLoader waere die Card beim naechsten
  # Neuladen weg — der Browser kennt sie, der Server nicht.
  test "#1658: die Hilfe-Card ueberlebt das Neuladen" do
    HelpCard.create!(key: "task", program_body: "Erklärung nach dem Neuladen")
    aufgabe = create_task(creator: @admin, title: "Musteraufgabe")
    anmelden(@admin)
    get "/tasks", params: { stack: "list:tasks,task:#{aufgabe.id},help:task" }
    assert_response :success
    assert_includes @response.body, "stack_card_help:task"
    assert_includes @response.body, "Erklärung nach dem Neuladen"
  end

  test "#1658: die Hilfe-Card selbst bekommt kein Fragezeichen" do
    anmelden(@admin)
    get help_card_path(key: "task")
    assert_not_includes @response.body, %(data-help-link-kind-value="help")
  end

  # ── R4: Titel, Stift, Umschalten ─────────────────────────────────────

  # Hans: „Den Bezug mit in den Kartentitel, also zum Beispiel
  # ‚Hilfe: Grundstück • Reiter Details'; das auch im Spine"
  test "#1658 R4: Titel und Ruecken nennen den Bezug" do
    anmelden(@admin)
    get help_card_path(key: "ki.master_data")
    erwartet = I18n.t("hilfe.titel_mit_bezug",
                      bezug: I18n.t("hilfe.bezug_mit_reiter",
                                    art: I18n.t("hilfe.arten.ki"),
                                    reiter: I18n.t("hilfe.reiter.ki.master_data")))
    # Einmal als Card-Titel, einmal als Beschriftung des Rueckens.
    assert_operator @response.body.scan(erwartet).size, :>=, 2
  end

  # Hans: „Statt ‚Notiz bearbeiten' ein Stift-Icon in der Abschnittstitel-Zeile"
  test "#1658 R4: der Stift steht in der Titelzeile, nicht als Text" do
    anmelden(@admin)
    get help_card_path(key: "ki.master_data")
    assert_includes @response.body, %(title="#{I18n.t("hilfe.bearbeiten")}")
    assert_includes @response.body, "click->description-toggle#edit"
  end

  # Hans: „Können sich Bearbeitung und Darstellung abwechseln … Also nicht
  # beides gleichzeitig übereinander anzeigen?"
  test "#1658 R4: das Schreibfeld liegt hinter der Darstellung" do
    HelpCard.create!(key: "ki.master_data", program_body: "Erklärung")
    anmelden(@admin)
    get help_card_path(key: "ki.master_data")
    assert_includes @response.body, %(data-description-toggle-target="preview")
    # Das Formular ist da, aber verborgen — sichtbar wird es erst per Stift.
    assert_match(/<form[^>]*data-description-toggle-target="form"[^>]*class="hidden"/, @response.body)
  end

  test "#1658 R4: ohne Schreibrecht gibt es weder Stift noch Formular" do
    HelpCard.create!(key: "ki.master_data", program_body: "Erklärung")
    anmelden(@mitarbeit)
    get help_card_path(key: "ki.master_data")
    # Die Mitarbeit darf die Notiz schreiben — also genau EIN Stift, nicht zwei.
    assert_equal 1, @response.body.scan("click->description-toggle#edit").size
    assert_includes @response.body, "Erklärung"
  end

  # Hans: „Das ‚Allgemein zu dieser Karte' würde ich weglassen; wenn die Karte
  # Reiter hat, gibt es zur Karte selbst keine Hilfe."
  test "#1658 R4: es gibt keinen Rueckfall auf die Karten-Hilfe mehr" do
    HelpCard.create!(key: "task", program_body: "Allgemein zur Aufgabe")
    anmelden(@mitarbeit)
    get help_card_path(key: "ki.master_data")
    assert_not_includes @response.body, "Allgemein zur Aufgabe"
  end

  # ── R5: Symbole im Text ──────────────────────────────────────────────

  # Hans: „Können die Lucide-Icons auch im Text angezeigt werden?"
  test "#1658 R5: Marker im Hilfetext werden zu Symbolen" do
    HelpCard.create!(key: "ki.master_data",
                     program_body: "Klicke :ui:karte_schliessen: oder :icon:check: an.")
    anmelden(@mitarbeit)
    get help_card_path(key: "ki.master_data")
    assert_includes @response.body, "<svg"
    assert_not_includes @response.body, ":ui:karte_schliessen:"
    assert_not_includes @response.body, ":icon:check:"
  end

  test "#1658 R5: die Symbol-Auswahl kennt Bedienelemente und Symbole" do
    anmelden(@admin)
    get help_icons_path
    assert_response :success
    assert_includes @response.body, ":ui:karte_schliessen:"
    assert_includes @response.body, ":icon:pencil:"
    assert_includes @response.body, I18n.t("hilfe.icons.bedienelemente")
  end

  # Die Auswahl steckt am Schreibfeld — wer nichts schreiben darf, braucht sie
  # nicht (und bekommt sie auch nicht).
  test "#1658 R5: die Auswahl haengt am Schreibfeld" do
    anmelden(@admin)
    get help_card_path(key: "ki.master_data")
    assert_includes @response.body, I18n.t("hilfe.icons.einsetzen")
    assert_includes @response.body, help_icons_path
  end

  # Das registrierte Bedienelement traegt seine Kennung im Markup — daran
  # erkennt der Beschriftungs-Modus, welchen Marker er kopieren soll.
  test "#1658 R5: Bedienelemente tragen ihre Kennung im Markup" do
    aufgabe = create_task(creator: @admin, title: "Musteraufgabe")
    anmelden(@admin)
    get "/tasks/#{aufgabe.id}/card"
    assert_includes @response.body, %(data-ui-icon="karte_schliessen")
    assert_includes @response.body, %(data-ui-icon="hilfe")
  end

  # ── R6: Beschriftungen nachschlagen ──────────────────────────────────

  test "#1658 R6: der Nachschlag findet den Schlüssel zum sichtbaren Text" do
    anmelden(@admin)
    text = I18n.t("knowledge.editors.relationships.target_placeholder")
    get help_bezeichnungen_path(text: text, bereich: "ki")
    assert_response :success
    daten = JSON.parse(@response.body)
    assert_equal "knowledge.editors.relationships.target_placeholder", daten["treffer"].first["schluessel"]
  end

  test "#1658 R6: die Suche findet Bezeichnungen nach dem sichtbaren Wort" do
    anmelden(@admin)
    get help_bezeichnungen_path(q: "beziehung")
    daten = JSON.parse(@response.body)
    assert daten["treffer"].any? { |t| t["schluessel"] == "knowledge.editors.relationships.title" }
  end

  test "#1658 R6: ohne Treffer bleibt die Antwort leer statt zu raten" do
    anmelden(@admin)
    get help_bezeichnungen_path(text: "Diesen Text gibt es nirgends im Programm")
    assert_equal [], JSON.parse(@response.body)["treffer"]
  end

  test "#1658 R6: der Hilfetext zeigt die Beschriftung, nicht den Schlüssel" do
    HelpCard.create!(key: "ki.master_data",
                     program_body: "Unter :feld:knowledge.editors.relationships.target_placeholder: eintragen.")
    anmelden(@mitarbeit)
    get help_card_path(key: "ki.master_data")
    assert_includes @response.body, I18n.t("knowledge.editors.relationships.target_placeholder")
    assert_includes @response.body, "hilfe-bezeichnung"
    assert_not_includes @response.body, ":feld:knowledge"
  end

  # ── R7: jedes Symbol ist zitierbar ───────────────────────────────────

  # Jedes Icon nennt seinen Namen, damit der Beschriftungs-Modus daraus
  # `:icon:<name>:` machen kann.
  test "#1658 R7: jedes Icon traegt seinen Namen im Markup" do
    aufgabe = create_task(creator: @admin, title: "Musteraufgabe")
    anmelden(@admin)
    get "/tasks/#{aufgabe.id}/card"
    assert_includes @response.body, %(data-icon="help_circle")
    # Das registrierte Bedienelement traegt zusätzlich seine Kennung — die Funktion gewinnt.
    assert_includes @response.body, %(data-ui-icon="karte_schliessen")
  end

  test "#1658 R7: auch nicht registrierte Symbole sind benannt" do
    anmelden(@admin)
    get help_icons_path
    assert_includes @response.body, %(data-icon="check")
  end

  # ── R9: Überschriften nennen ihren Schlüssel ─────────────────────────


  # Wer eine Überschrift so zitiert, bekommt genau deren Text.
  test "#1658 R9: der zitierte Schlüssel ergibt denselben Text wie die Karte" do
    HelpCard.create!(key: "ki.master_data",
                     program_body: "Der Abschnitt :bereich:knowledge.editors.address.title: enthält die Anschrift.")
    anmelden(@mitarbeit)
    get help_card_path(key: "ki.master_data")
    assert_includes @response.body, I18n.t("knowledge.editors.address.title")
    assert_includes @response.body, "hilfe-bereich"
  end

  # ── R10: Bearbeiten wie bei einer Antwort ────────────────────────────

  # Hans: „Das Stifticon wird zum Häkchen, mit dem ich die Bearbeitung beende.
  # Ich kann andere Karten aufrufen, ohne die Bearbeitung zu beenden."
  test "#1658 R10: Stift und Häkchen bilden ein Paar" do
    anmelden(@admin)
    get help_card_path(key: "ki.master_data")
    # Je Bereich einer von beiden — Notiz und Erklärung.
    assert_equal 2, @response.body.scan("click->description-toggle#edit").size
    assert_equal 2, CGI.unescapeHTML(@response.body).scan("mousedown->description-toggle#save").size
    assert_includes @response.body, %(title="#{I18n.t("hilfe.fertig")}")
  end

  # Der Kern der Anforderung: KEIN Speichern beim Verlassen des Feldes —
  # sonst endet die Bearbeitung, sobald man eine andere Karte anklickt.
  test "#1658 R10: das Schreibfeld speichert nicht beim Verlassen" do
    anmelden(@admin)
    get help_card_path(key: "ki.master_data")
    assert_not_includes @response.body, "blur->"
    assert_not_includes @response.body, "onblur"
  end

  # Wenn nicht beim Verlassen gespeichert wird, müssen die beiden Netze halten:
  # Rückfrage beim Schließen der Card und Entwurfsspeicher im Browser.
  test "#1658 R10: ungespeicherte Änderungen sind abgesichert" do
    anmelden(@admin)
    get help_card_path(key: "ki.master_data")
    # dirty-mark markiert nur — der Stapel fragt beim Schließen. `dirty-warn`
    # wäre falsch: Es warnt bei JEDEM Turbo-Wechsel, und das Öffnen einer
    # anderen Karte ist einer (gemessen am 18.09.).
    assert_includes @response.body, %(data-controller="dirty-mark")
    assert_includes @response.body, "input->dirty-mark#mark"
    assert_not_includes @response.body, "dirty-warn"
    assert_includes @response.body, %(data-draft-persist-key-value="help.ki.master_data.program")
  end

  # Derselbe Editor wie bei Aufgaben und Antworten.
  test "#1658 R10: das Schreibfeld nutzt den gemeinsamen Editor" do
    anmelden(@admin)
    get help_card_path(key: "ki.master_data")
    assert_includes @response.body, %(data-cm6-editor-active-value="true")
    assert_includes @response.body, %(data-cm6-editor-target="textarea")
  end

  # ── R10: Daten für die Vorschau im Editor ────────────────────────────

  # Der Editor zeigt Marker als Symbol bzw. Wort an — beides kennt nur der
  # Server. Geliefert wird genau das Angefragte, nicht der ganze Bestand.
  test "#1658 R10: Symbole werden einzeln geliefert" do
    anmelden(@admin)
    get help_symbole_path(namen: "copy,check,gibtesnicht")
    assert_response :success
    daten = JSON.parse(@response.body)["symbole"]
    assert_includes daten.keys, "copy"
    assert_includes daten.keys, "check"
    assert_not_includes daten.keys, "gibtesnicht"
    assert_includes daten["copy"], "<rect"
    # Gerendert, nicht roh gelesen: Die Dateien beginnen mit einem
    # ERB-Kommentar, der sonst als Text im Editor stünde.
    assert_not_includes daten["check"], "<%#"
  end

  test "#1658 R10: ein unbrauchbarer Symbolname wird abgewiesen" do
    anmelden(@admin)
    get help_symbole_path(namen: "../../config/database")
    assert_equal({}, JSON.parse(@response.body)["symbole"])
  end

  test "#1658 R10: Beschriftungen kommen auch vorwärts" do
    anmelden(@admin)
    get help_bezeichnungen_path(keys: "knowledge.editors.relationships.target_placeholder,gibt.es.nicht")
    daten = JSON.parse(@response.body)["texte"]
    assert_equal I18n.t("knowledge.editors.relationships.target_placeholder"), daten["knowledge.editors.relationships.target_placeholder"]
    assert_not_includes daten.keys, "gibt.es.nicht"
  end

  # `:ui:karte_schliessen:` nennt eine FUNKTION — welches Symbol sie trägt, sagt das
  # Verzeichnis. Ohne diese Auflösung zeigte der Editor für Bedienelemente
  # nichts (gemessen am 18.09.).
  test "#1658 R10: Bedienelemente werden zu ihrem aktuellen Symbol aufgelöst" do
    anmelden(@admin)
    get help_symbole_path(elemente: "karte_schliessen,bearbeiten,gibtesnicht")
    daten = JSON.parse(@response.body)["elemente"]
    assert_includes daten.keys, "karte_schliessen"
    assert_includes daten.keys, "bearbeiten"
    assert_not_includes daten.keys, "gibtesnicht"
    # karte_schliessen trägt heute das Kopier-Symbol.
    assert_equal JSON.parse(@response.body.dup)["elemente"]["karte_schliessen"].present?, true
  end

  # ── R11: Farbe, Überschriften, Zeigen ────────────────────────────────

  # Hans: „Icons in derselben Farbe darstellen, wie die Text-Marker."
  test "#1658 R11: Symbole tragen dieselbe Farbklasse wie die Wörter" do
    HelpCard.create!(key: "ki.master_data", program_body: "Klicke :ui:karte_schliessen: an.")
    anmelden(@mitarbeit)
    get help_card_path(key: "ki.master_data")
    assert_match(/<svg[^>]*class="[^"]*hilfe-bezeichnung[^"]*hilfe-symbol/, @response.body)
  end

  # Hans: „Kann man die Marker für Texte auch als Überschriften formatieren?
  # Dann würden sie die Farbe behalten." — Das geht bereits; hier festgehalten,
  # damit es so bleibt.
  test "#1658 R11: ein Marker in einer Überschrift bleibt Überschrift UND Marker" do
    HelpCard.create!(key: "ki.master_data",
                     program_body: "## :bereich:knowledge.editors.relationships.title:\n\nText.")
    anmelden(@mitarbeit)
    get help_card_path(key: "ki.master_data")
    assert_match(%r{<h2[^>]*><strong class="hilfe-bezeichnung hilfe-bereich[^"]*"[^>]*><em>#{Regexp.escape(I18n.t("knowledge.editors.relationships.title"))}</em></strong></h2>},
                 @response.body)
  end

  # Hans: „Können die Marker im Hilfetext als Highlighter funktionieren?"
  test "#1658 R11: jeder Marker trägt sein Ziel und ist anklickbar" do
    HelpCard.create!(key: "ki.master_data",
                     program_body: "Klicke :ui:karte_schliessen: bei :feld:settings.users.col_email:.")
    anmelden(@mitarbeit)
    get help_card_path(key: "ki.master_data")
    assert_includes @response.body, %(data-hilfe-art="ui")
    assert_includes @response.body, %(data-hilfe-schluessel="karte_schliessen")
    assert_includes @response.body, %(data-hilfe-art="feld")
    assert_includes @response.body, %(data-hilfe-schluessel="settings.users.col_email")
    assert_includes @response.body, "hilfe-zeigbar"
    assert_includes @response.body, "click->hilfe-zeiger#zeigen"
  end

  # ── R12: Feldbeschriftungen nennen ihren Schlüssel ───────────────────



  # ── R13: auch dt/label/th nennen ihren Schlüssel ─────────────────────
end
