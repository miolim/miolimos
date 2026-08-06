# System-Tests

System-Tests treiben einen echten Browser (headless Chromium via
[Cuprite](https://github.com/rubycdp/cuprite)) gegen einen Puma-Server
im selben Prozess. Sie verifizieren das Zusammenspiel von Rails,
Stimulus, Turbo und Browser-APIs — Dinge, die Unit-Tests nicht abdecken.

## Wann verwenden?

- **Stimulus-Controller mit DOM-Manipulation** (`paragraph_actions`,
  `blade_stack`, `wikilink_autocomplete`, ...) — Unit-Tests reichen nicht,
  weil sich der Wert aus dem realen Lifecycle (connect, render, hover)
  ergibt.
- **Turbo-Streams + Frames** — wenn Verhalten erst nach mehreren
  Roundtrips sichtbar wird.
- **Browser-Features** — Clipboard, scrollIntoView, History-Persist.

Fuer reine Controller-/View-Logik weiterhin
`ActionDispatch::IntegrationTest` (unter `test/controllers/`) nehmen —
schneller und stabiler.

## Lokal starten

```bash
bin/rails test:system               # alle System-Tests
bin/rails test test/system/...      # einzelner Test
HEADED=1 bin/rails test test/...    # mit sichtbarem Browser-Fenster
```

System-Tests laufen NICHT als Teil von `bin/rails test`. `bin/deploy`
beruehrt sie nicht — Asset-Pipeline und Chromium-Start kosten Zeit, die
wir bei jedem Push nicht zahlen muessen.

## Voraussetzungen

- Chromium oder Chrome installiert (`/usr/bin/chromium-browser` oder
  `/usr/bin/google-chrome` reicht).
- Erster Run kompiliert Assets via Tailwind — kann 5-15s dauern.

## FALLE: JS-Aenderungen brauchen erst ein Precompile (#1283, 2026-08-06)

Propshaft benutzt im Test-Env den **Static**-Resolver
(`Rails.application.assets.resolver` → `Propshaft::Resolver::Static`).
Der Browser bekommt also das, was in `public/assets/` liegt — **nicht**
den Stand aus `app/javascript/`. Wer einen Stimulus-Controller aendert
und direkt `bin/rails test test/system/...` startet, testet das JS des
letzten `bin/deploy`.

Das faellt nicht auf, weil der Test gruen wird — er prueft nur die alte
Datei. Bei #1283 waren so drei Laeufe (inkl. eines Rot-Checks) ohne
Aussage, bevor es aufflog.

Vor dem Lauf deshalb:

```bash
RAILS_ENV=production bin/rails assets:precompile   # gleiche Env wie bin/deploy
bin/rails test test/system/...
```

`RAILS_ENV=production` bewusst: `public/assets/` bedient auch die
laufende Instanz, und so liegt dort genau das, was `bin/deploy` auch
gebaut haette. Gegenprobe, dass die Aenderung wirklich drin ist:

```bash
grep -c meineNeueFunktion public/assets/controllers/mein_controller-*.js
```

## Konventionen

- Erbe von `ApplicationSystemTestCase` (NICHT von `ActiveSupport::TestCase`).
- Login via `login_as(actor)`-Helper (in `application_system_test_case.rb`).
- FileProxy-isolierten Testlauf in `setup` durchziehen, in `teardown`
  `BASE_PATH` zurueck-restoren (siehe `paragraph_actions_test.rb` als
  Vorlage).
- Toolbars mit `opacity-0`/`hidden`-Klassen brauchen `visible: :all`,
  sonst sieht Capybara sie nicht.
