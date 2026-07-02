# miolimOS Inbox — Browser-Extension (Chrome MV3)

Sendet die aktuelle Tab-URL (plus optionaler Notiz) an die miolimOS-
Inbox via `POST /api/v1/inbox_items`. Mit `auto: true` läuft der
Auto-Processor sofort (z.B. YouTube-Transkript).

## Installation (unpacked)

1. In miolimOS: **Einstellungen → Agenten → Neu**, einen Agent
   ("Browser-Extension") anlegen. Den `api_token` notieren. Dem
   Agent die Capability `InboxItem: read, create` granten.
2. In Chrome: `chrome://extensions` → Entwicklermodus aktivieren →
   "Entpackte Erweiterung laden" → diesen `browser_extension/`-Ordner
   wählen.
3. Beim ersten Start öffnet sich die Options-Seite. Base-URL
   (`https://os.miolim.de`) und API-Token eintragen, speichern.
4. Toolbar-Icon erscheint. Klick → Popup mit aktuellem Tab.

## Updates

Code-Änderungen in `popup.js`, `background.js` etc. werden erst nach
"Aktualisieren" auf `chrome://extensions` aktiv.

## Firefox

`manifest.json` ist MV3, das Firefox seit ~110 unterstützt — kann
aber Quirks haben. Falls nötig: in `about:debugging` als
"Temporäres Add-on" laden.
