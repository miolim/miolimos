# Changelog

All notable changes to miolimOS are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Versions before the first public release carry a `0.MINOR.PATCH` number; while
the major version is `0`, the API and data model may still change between minor
versions. See [UPGRADING.md](UPGRADING.md) for how to move between versions.

## [Unreleased]

_Changes landing on `main` but not yet released are collected here. When a
release is cut, this section is renamed to the new version and a fresh
`Unreleased` is started — see [docs/releasing.md](docs/releasing.md)._

### Added

- A document now records what kind of document it is (#1336). Incoming
  documents already had their type recognised on import — invoice,
  official notice, insurance policy, letter, contract — and then threw it
  away: everything filed as an invoice, indistinguishable afterwards. The
  type is now kept as a document type of its own, shown as a badge in the
  invoice list and on the card, and correctable in the editor. It is
  deliberately separate from the existing kind (invoice/quote), where the
  number ranges, rendering and e-invoicing hang — a new value there would
  quietly falsify counters and filters. Existing documents are unchanged;
  an empty type simply means "not recorded". Notices and insurance
  policies are also recognised as their own types on import now instead
  of collapsing into "other"; they still file as a document record only,
  without becoming an invoice — a document that carries no payment
  obligation cannot be represented yet, and would show up as an open item.
  That is what the next step opens up. The list of document types is
  deliberately open-ended: a further type is one entry plus its two
  translations, no migration and no new code path. It is therefore stored
  under its name rather than as a number, so the database says `bescheid`
  instead of `1` and no numbering can drift apart between an installation
  and a fork. Recognition and the editor's drop-down read the same list,
  so a new type is added in one place and is immediately both recognised
  and selectable.
- Bank accounts, statements and transactions exist as records of their own
  (#1337, first cut). Bookkeeping against a bank account is not specific to
  any one trade, and it now lives here rather than only in the property
  management fork it grew up in. This cut brings the entities alone — no
  import formats and no matching of payments against what they settle, both
  of which follow. Transactions carry the sign the statement shows them
  with, remember which statement they came in on, can be marked as
  deliberately unassigned (a loan instalment, an account fee, a transfer
  between your own accounts) so they stop asking for a decision, and are
  protected against being imported twice by a fingerprint unique per
  account. A transaction can also point at the party it involves as a link
  rather than only carrying the name printed on the statement.
- Whether an incoming document becomes a record of a debt is now decided by
  the amount payable, not by what kind of document it is (#1338). Until now
  only something recognised as an invoice ever became one; an insurance
  policy with a premium or a land transfer tax assessment did not, although
  both plainly oblige you to pay. Anything carrying an amount now does,
  whatever it is called, and the kind is kept for filing as before. A
  document that merely sets out future payments still gets no obligation and
  so appears in no list of open items. Extraction was widened to match: it
  now reads the payment fields whenever a document obliges payment, takes
  the amount demanded rather than the largest figure on the page — the tax
  assessed, not the purchase price it is calculated from — and always
  records at least one line item, so a document can no longer end up at
  €0.00.
- A document can now carry any number of payment obligations — none, one or
  many (#1336). Until now a document had exactly one due date, which made a
  property tax assessment with four quarterly instalments, or an insurance
  policy paid in instalments, impossible to record. Worse was the opposite
  case: a document that establishes no claim at all — an assessment that
  merely sets future prepayments, a contract, a bank statement — still
  carried an amount and a date, and therefore appeared as an open item and
  as overdue. A payment obligation is now its own thing, with its own
  amount, due date and label ("instalment 2 of 4"), and a document without
  one is simply not an open item. Nobody has to remember a rule for that to
  hold.
  The obligation knows who it belongs to and which document announces it,
  which keeps the two apart: an assessment can announce instalments that
  belong to a lasting arrangement elsewhere, without claiming them itself.
  Amounts are signed by the direction the money moves as seen from here, so
  a credit note settled by a refund is recognised as settled rather than
  quietly counting as unpaid. Settlement is recorded as an amount, not a
  flag, so an obligation can be partly settled.
  Consequently the document's own due date is gone — with four instalments
  there is no such thing — and the card shows the next open one instead. The
  payment status is no longer set by hand but derived: open while anything
  is outstanding, settled once nothing is, and empty when there is no
  obligation at all. Existing documents migrate without loss: each one that
  had a due date receives exactly one obligation carrying it.
- Full search results as their own card (#1321). The quick search in the
  top bar stays the fast glance — it still shows the first eight rows per
  category — but it no longer hides how much it left out: press Enter, or
  use the new "Show all results" row at the bottom of the drop-down, and
  the complete result set opens as a card in the workspace. It is grouped
  by entity as before, each section carrying its true hit count in the
  header. Sections start collapsed, so you open the one you actually
  want; long sections load twenty rows at a time. The search term travels
  in the card's id, so a reload or a bookmarked workspace brings the same
  results back.
- Search now covers documents, invoices, topics, sources, follow-ups and
  the inbox, and it reads the body of a message, not just its subject
  (#1321). Before, a letter was only findable through the text of its
  body note — and then showed up as a knowledge hit rather than as the
  document it belongs to.
- Back/forward arrows in the top bar, left of the search field (#1198):
  they step through the workspace's history like a browser — a card just
  closed comes back, a card that replaced several others is undone to
  the replaced set. Only visible on pages with a card workspace; greyed
  out when there is no step in that direction. Same mechanics as the
  existing Alt+←/→ shortcut and the arrows on the knowledge workspace,
  which both stay.

### Fixed

- Adding a card no longer drags the card shelf along (#1283). When the
  stack was scrolled so that space was left on the right, a quick-add
  used to scroll it back until the space was filled and the new card sat
  flush right. The position now stays put and the card is simply
  appended — the shelf only moves when that is what it takes to show the
  new card, and then only as far as needed. Refreshing a card leaves the
  position alone entirely: a refresh replaces the card in place, which
  looked like an append to the observer that watches the stack.

### Added

- The quick person form in the top bar now also asks for gender (#1267).
  It is optional and empty stays "not stated", but filling it in right
  away is what lets a letter open with "Sehr geehrte Frau Schnell"
  instead of the neutral form — the create path already accepted the
  value since #1090, only the field was missing.

- "Complete contact data" now also takes pasted text (#1250): the card
  tool that used to need an imprint URL accepts a copied email signature
  or business card just as well, and fills the same empty fields. Values
  with a checkable shape — email address, phone, fax, VAT ID — must
  appear in the pasted text itself, so a smoothed-over digit or an
  invented address cannot slip in; a differently written but identical
  phone number still passes. Fetching a page stays lenient, because
  imprints often obfuscate addresses and resolving that is a gain.

- `ops/export-instance-keys.sh` collects the keys of every instance on the
  machine into one directory, named after the instance they belong to
  (#1220). `config/master.key` and `config/credentials.yml.enc` are
  deliberately kept out of git and out of the backup, so their only second
  copy is whatever the operator puts in a password manager — this makes
  assembling that copy a single command instead of a hunt. Instances that
  keep their secrets in a `.env` file are included; the copies are
  owner-readable only and the script says to delete them once they are
  filed away.

### Fixed

- Wide cards no longer peek out to the right of the front card (#1228).
  When the workspace is scrolled all the way left so that only spines and
  the front card remain, a card that is wider than the front one used to
  stay visible past its right edge — stacking order decides who is on
  top, not how far they reach. Each card is now clipped at the left edge
  of the card in front of it, which is a no-op whenever cards sit side by
  side without overlapping.

- The daily operations report no longer cries wolf about changed instance
  keys (#1220). Several instances on one machine share the report's state
  file, and they recorded their key fingerprints under the same generic
  labels — so each run overwrote the other's entry, and since the
  instances hold different keys, every run reported a change that had
  never happened. Exactly the daily false alarm this report exists to
  avoid. Entries now carry the instance name, and the alert names the
  file's path, so it is clear which key is meant.

- Uploading a logo on a person or organization works again (#1211): the
  upload form was missing its multipart encoding, so the file arrived as
  a plain string, the server errored, and the card showed "Content
  missing" instead. Now guarded server-side as well, and covered by a
  browser test that uploads through the real form.

- Editing a task title is no longer interrupted by live updates (#1175).
  The card header refreshes that mirror status, WIP marker, and title
  changes into every open card used to replace the whole header — kicking
  the cursor out of the title field mid-typing whenever an agent's inbox
  run touched the task (WIP marker on, comment, done, WIP marker off: four
  kicks per run). The header now morphs instead, which leaves the focused
  field — value and cursor — untouched and updates everything around it.

## [0.3.5] - 2026-07-27

### Added

- Letters can name their addressee freely (#1171, adopted from immoOS #1069):
  an optional "addressee in the address window" field on the letter replaces
  the recipient's registered name in the DIN address window — "Eheleute
  Mustermann" instead of the single person the letter is technically linked
  to. The address still comes from the linked recipient. Deliberately no
  derivation from matching surnames: that guesses wrong for siblings, flat
  shares, and double names — on the envelope of all places.

- Letters with a "Zahlbetrag" info-block field now render a GiroCode
  (EPC payment QR) below the letter text, with IBAN/BIC taken from the
  issuer's identifiers or first bank account — same mechanics as on
  invoices (#1171, adopted from immoOS #1157).

- People and organizations can now carry a logo (#1168): upload it in the
  card's master-data section (stored as a regular image entry, removable
  without deleting the image). The letterhead of generated documents shows
  the issuer's logo instead of the plain name when one is set.

- Ctrl+click (Cmd+click on the Mac) on a list item appends its card to the
  workspace — same as the plus icon — instead of replacing the current card
  (#1151).

- Ctrl+double-click on a card's resize handle adopts the card's current
  width as the new default width for that card kind (saved to Settings →
  Preferences); a plain double-click resets to that default (#1152).

- Holding Ctrl while dragging a card's resize handle inverts the direction:
  moving the mouse left makes the card wider. Useful for the rightmost card,
  where the window edge leaves no room to drag right (#1154).

- Autosave fields now confirm what they do. Fields that save on leaving them —
  invoice amounts, task fields, document metadata, and the like — briefly show
  a green check mark at the field once saving succeeded, and keep a red border
  (with an explanatory tooltip) when it failed, until the value is changed
  again. One mechanism covers every autosave field in the app (#1114).

- The top bar is now customizable per user (Settings → Preferences → Top bar):
  every icon — the quick-create row, the time timer, dark mode, keyboard
  shortcuts, labeling mode, and the diagnostic snapshot — can be placed in the
  left zone (after the search field) or the right zone in any order, or hidden
  entirely. Search, your name, and logout always stay. Works exactly like the
  sidebar editor: drag between the columns, reorder within, reset to default
  (#1109).
- Merging duplicate people and organizations. When the same real person got
  recorded twice — typically because the mail sync auto-created a contact for
  an address that had been removed from the "real" entry — the duplicate's
  card now offers "Zusammenführen in …". Picking the target moves everything
  the duplicate holds (contact points, addresses, bank accounts, identifiers,
  communications, mentions, relations, affiliations, source authorship, notes
  body) onto the target, keeps the duplicate's name as an alias so existing
  `[[wiki links]]` keep resolving, and puts the emptied duplicate into the
  trash. The API endpoint `POST /knowledge_items/:uuid/merge_into` performs
  the same full merge (it used to move source authorship only) and returns a
  per-category report of what moved (#1075).

- Gender and salutation on people. A person carries an optional gender
  (female / male / diverse, blank means not stated) and an optional free-text
  salutation. A letter that has no salutation of its own now derives one from
  its recipient — "Sehr geehrte Frau Mustermann" instead of the blanket
  "Sehr geehrte Damen und Herren" that every letter used to open with. The
  free-text field always wins, because a catalogue cannot spell "Liebe Anna"
  or "Frau Prof. Dr. Meier"; where nothing is stated, the neutral form stays.
  Both fields travel in the Markdown front matter like the rest of the master
  data.

- Academic title on people. A person carries an optional free-text academic
  title ("Dr.", "Prof. Dr.") as its own master-data field. It appears in the
  derived letter salutation ("Sehr geehrte Frau Prof. Dr. Meier") and in the
  name line of the DIN address window ("Prof. Dr. Erika Meier"). Like gender
  and salutation it travels in the Markdown front matter.

- Register court and commercial-register number as their own ID types on people
  and organisations. They are two fields, not one: an HRB number is only
  unique together with the court that keeps it, and letterheads and invoices
  quote the two separately. Completing contact data from an imprint now splits
  the register line accordingly ("Amtsgericht Lübeck HRB 12345" becomes a
  *Registergericht* and a *Handelsregisternummer*); a wording it cannot parse
  is still kept whole, so nothing is lost (#1094).

- Operations monitoring for self-hosted installs. `ops/watchdog/` carries a
  cron-driven watchdog that probes every known instance on `127.0.0.1/up` and
  reports the *transition*: a service that once answered and stopped is loud,
  one that has never answered stays silent, and a service still down does not
  repeat itself. `rails ops:daily_report` mails a daily operations summary
  (services, database backup, unpushed commits) — it is sent every day even
  when everything is green, so that its absence is itself the alarm.
  `rails ops:report_preview` prints the same report without sending it.
  It no longer warns about an access token nearing expiry — that token is
  refreshed automatically, so the warning would have fired on every healthy
  day, and a daily alarm without cause is how monitoring gets ignored. The
  report also watches the instance keys — `config/master.key` and
  `credentials.yml.enc` are deliberately kept out of the backup (putting them
  in the data archive would let one passphrase unlock both data and keys), so
  their only second copy is whatever the operator stored elsewhere; the report
  records a fingerprint and speaks up when it changes, because a rotated key
  silently invalidates that copy. It also checks its own delivery path — an expired Google credential
  silently disables *all* outgoing mail, including portal magic links — and
  falls back to filing itself as a knowledge item when the mail cannot be
  sent (#1076).
- The nightly backup now includes the instance data directories, not just the
  databases. Attachments (invoices, settlement documents, meter photos,
  profile images) live in the file system with only their path in the
  database, so a database-only backup restored into a fresh machine would
  have produced a complete-looking database full of references to files that
  no longer exist. They are archived in the same run and under the same
  timestamp as the dump — a restore from two different points in time is
  worse than one known to be inconsistent — encrypted before upload and kept
  off-site only, since a second local copy of local files protects nothing.
  Exclusions are set per directory: a data directory whose git history is the
  only copy keeps it (the app serves per-note version history and restore from
  that repository), while one mirrored to GitHub leaves it out. The restore
  procedure is documented in `ops/backup/DISASTER_RECOVERY.md` (#1076).
- Postal addresses can carry a validity period (`valid from` / `until`, either
  side optional). A person who moves keeps the former address on record while
  letters go to the one valid today — `mailing_address` and `primary_address`
  pick among the addresses valid on a given date, and select none at all when
  none is valid. An empty address field is the signal that something is
  missing; a silently substituted expired address looks right and goes out
  wrong. Existing addresses have no period and stay unlimited. The period is
  editable in the address editor and travels through the API (#1073).

- `ops/fresh-clone-check.sh` runs the suite in a throwaway clone. The deploy
  gate runs in the working checkout — with the gitignored key files, a grown
  `tmp/`, and the calling shell's environment — so a test that silently
  depends on any of those is green there and red for anyone who clones the
  repository. Two such tests were found on the same morning; both would have
  shown up here (#1076).

### Changed

- All user-visible texts now speak plain language instead of internal
  component names (#1115): the dashboard panel "Prozess-Edge" is now "Nächste
  Schritte & Wartepunkte"; "Card"/"Blade" became "Karte", "Stack" became
  "Arbeitsfläche", "Spine" "Kartenrücken", "Trail" "Schritt", "Work-Tree"
  "Gliederung", the render modes are now "Dokument-Ansicht"/"Zweck-Mittel-
  Ansicht"/"Leseansicht"; "KI"/"Item" is now "Eintrag", "Wikilink"
  "Verknüpfung", "Highlight" "Hervorhebung", "Topic" "Thema", "Pin"
  "anheften"; admin terms like "Capabilities" ("Berechtigungen"), "Owner
  (Actor)" ("Gehört zu (Konto)"), "Diagnose-Snapshot" ("Diagnose-Bericht")
  and "Quickadd-Picker" ("Schnellanlage-Auswahl") follow suit. Internal
  names in code and IDs are unchanged, and previously hardcoded texts
  (card close menu, keyboard-shortcut help, history panel title, multi-
  instance badge, PDF tooltip) moved into the locale files.

- The card-width preferences (Settings → Preferences) now use the same kind
  names the workspace actually looks widths up under: "source" became "src",
  "list_tasks" "list:tasks", "topic_list" "list:topic" — under the old names
  these settings never had any effect. Saved preferences are migrated
  automatically; the never-used "list_default" entry was dropped (#1152).

- List entries that are open as a card in the stack are now marked in one way
  only — the red colouring. The older marker (bold plus a chevron button that
  was injected at the start of the row and visibly indented it) is gone (#1067).
- Clicking an entry that is already open as a card jumps to that card instead
  of opening a second copy. This used to depend on the click happening inside a
  list blade, so rows shown inside a normal card (invoices on a person, for
  instance) opened a duplicate every time. The plus icon still adds another
  copy on purpose (#1067).
- Closing a card leaves the rest of the stack where it is. The cards to the
  left keep their scroll position instead of sliding along, and only the cards
  to the right move up to fill the gap. The focus follows only when the closed
  card actually held it — then to the card on its right, or, if there is none,
  to the one on its left. Closing a background card no longer pulls the focus
  away from the card you were working in, and the click on the closing cross
  itself no longer focuses the card it is about to remove (#1091).
- This now holds in every situation: when the remaining cards to the right are
  not wide enough to fill the viewport — or the closed card was the rightmost —
  an invisible placeholder at the end of the stack keeps the scroll width, so
  the cards on the left stay put and free space simply opens up on the right.
  That free space is a real place: you can scroll into it and back out, and
  closing cards from the left keeps growing it. It fills back up continuously
  as cards slide in front of it while scrolling left — never with a sudden
  snap — and shrinks only when newly opened cards take its room. Plain
  scrolling creates it too: swiping left past the last card shelves one more
  card per gesture into the spine pile on the left, growing the free space on
  the right until only the rightmost card remains open; swiping back unshelves
  them one by one (#1091).

### Fixed

- Amount inputs now understand both decimal conventions (#1171, adopted from
  immoOS #1170). All amount parsing goes through one comma-aware parser:
  "1.234,56" used to become a payment QR code over 1.23 € (the GiroCode
  field), and silently fell back to 0 in invoice lines and printable
  amounts; "1.234" without decimals is still read as a thousands separator.

- With very many cards on the workspace, shelving now works all the way to the
  end: card spines pack tighter as soon as the spine piles plus the widest card
  would exceed the container, so the rightmost card always collapses down to
  its spine and no spines disappear behind an open card any more. Previously
  the fixed 28px spine offsets grew wider than the viewport, leaving part of
  the rightmost card's content standing and hiding newly shelved spines behind
  it. The outermost card always keeps a full-width spine slot when it docks on
  the right, so it reads as a proper spine rather than a few-pixel sliver of
  content — only the deeper pile slots shrink. Card layout is also re-synced
  after each card finishes loading — the initial layout used to measure cards
  before their content arrived (#1167).

- The topbar search field no longer erases itself while typing. Since the
  quick-create controller moved onto the whole header (#1109), its
  after-submit cleanup also caught the search form: every debounced search
  request reset the field mid-typing while the results kept showing the hits
  for the text typed so far. The cleanup now only targets forms inside the
  quick-create slots (#1161).

- Saving a person without touching their contact data no longer wipes it.
  Internal saves that did not carry contact points, affiliations, or
  relationships — marking a person as superseded, for instance — silently
  deleted all three from the person. Absent data is now left untouched;
  explicitly clearing the last entry in the editor still deletes it (#1075).

- The red marking now also reaches entry types whose stack prefix differs from
  their kind (`inbox_item`, `tree_focus`, `topic_props`, `tag_list`): the
  highlight derived the id from its own second copy of the kind-to-stack-id
  table, which only knew a few special cases, so those rows never turned red.
  Both paths now read the one routing table (#1067).
- "Complete contact data from a URL" in the card toolbar is usable again. Its
  form was a plain `<details>` panel that stayed inside the card's scroll box,
  so it was cut off or covered by the card next to it and the submit button
  could not be hit. It now uses the same detached popover as the other card
  tools (#1093).

- Docker Compose now persists the application's files, not just its database.
  The `web` service had no volume at all, so everything written to disk lived
  inside the container: the knowledge Markdown and — the part that cannot be
  reconstructed — every attachment. A container rebuild left a
  complete-looking database full of references to files that no longer
  existed, without an error. Two named volumes now cover the data path and
  Active Storage (#1060).
- The daily operations report no longer prints key fingerprints. They are kept
  in its state file, where the comparison happens; the report only says whether
  a key changed. What the reader needs is the answer, not the value (#1076).
- The disaster-recovery runbook now produces an instance that actually works.
  Rehearsing it end to end for the first time showed two defects that only
  surface *after* a restore: `pg_restore --no-owner` leaves the tables owned by
  whoever ran it, so the application — connecting as its own database user —
  got `permission denied` on data that was fully present; and the `cache`/
  `queue` databases are deliberately not backed up but still required, so the
  restored instance booted, answered its health check, and then failed on the
  first background job. Both steps are corrected and verified, and the runbook
  gained a section on rehearsing safely on a live machine (#1080).
- The test suite no longer depends on `MIOLIMOS_HOST` from the calling shell.
  Tests that assert on link handling were written against the default host, so
  running them with a different one — anyone self-hosting under their own
  domain, or a deploy script that exports the instance host before its test
  gate — turned the suite red with nothing wrong in the application. The test
  environment now pins the host (#1076).
- The daily report now also reports the mirror case: a production database — or
  an instance data directory — that exists on the machine but is covered by no
  backup at all. The nightly job can
  only miss what it knows about, so a newly created instance database is simply
  never dumped — no error, no log line, nothing to notice. Coverage is derived
  from what the last run actually did (its log), not from the list in the
  script: a list says what was intended, a log says what happened (#1076).
- The nightly database backup now tells "not created yet" apart from "was here
  yesterday". A database listed for backup that has since been renamed or
  dropped used to be skipped as silently as one that does not exist yet, and
  the run still finished with `errors=0` — so a production database could fall
  out of the backup unnoticed. A missing database that has an earlier dump on
  disk is now reported as `MISSING` and fails the run (which also trips the
  dead-man's switch); one with no history stays silent as before. Added
  `ops/backup/selftest.sh`, which exercises both cases without a database
  (#1064).
- Returning to the dashboard no longer rebuilds the card stack from scratch:
  the server now renders the last open stack from the stored snapshot instead
  of shipping only the dashboard blade and letting the browser re-fetch every
  other card one after another. One request instead of N, and no second build
  flashing over the cached page. An explicit `?stack=` (or a legacy `?task=`
  link) still wins (#1066).
- Docker Compose now actually works on `http://localhost:3000`: production mode
  forced SSL unconditionally, so the documented local start redirected to an
  HTTPS endpoint nobody serves, and Action Cable rejected the http origin.
  `force_ssl`, `assume_ssl` and the Cable origin now follow `MIOLIMOS_PROTOCOL`
  (default `https`, so proxied installs are unaffected); `MIOLIMOS_CABLE_ORIGINS`
  overrides the origin list when the browser sends a port (#1060).
- @-mentions treat `-`, `_` and spaces as equivalent when resolving the actor:
  `@immoos-builder` now finds the actor named `immoos_builder` instead of
  rendering a missing-pill without notification (#1058).
- Bolded @-mentions (`**@slug**`) now create an actor mention: the raw-body
  scan that feeds the agent inbox missed mentions directly behind emphasis
  markers, so the pill rendered but the mentioned agent was never notified
  (#1058).
- The PDF stack card no longer 500s on non-ASCII titles (`·`, umlauts):
  the base64url payload is now forced to UTF-8 with an invalid-encoding
  guard (#1058, adopted from immoOS #1042).
- Stack-highlight opt-out: elements marked `data-stack-no-highlight` (e.g.
  nested deeplinks inside a clickable row) no longer tint their surrounding
  row (#1058, adopted from immoOS #1020).

## [0.3.4] - 2026-07-18

### Added

- Person and organization cards get an "Invoices" tab whenever the contact
  is party to an invoice (issuer or recipient): incoming invoices (contact =
  issuer) and outgoing invoices (contact = recipient) are listed as separate
  sections, each row opening the invoice in the blade stack (#972, adopted
  from immoOS via #1057).
- PDFs open in a stack card instead of a browser tab: the PDF action on
  document and invoice cards and the saved PDF versions ("Stände"/received
  documents) in the artifacts section now append an embedded PDF viewer card
  to the blade stack — with a stable stack id that survives reloads and
  stack restore, and a toolbar action to still open the raw PDF in a browser
  tab. Print view, signed PDF and ZUGFeRD keep opening in the tab (#1025,
  adopted from immoOS via #1057).

## [0.3.3] - 2026-07-18

### Added

- Organizations get an optional "legal form" field (GdWE, GmbH, UG, AG, GbR,
  OHG, KG, eG, e. V., sole proprietorship, other): a select on the
  organization's master-data section and in the create form. The value
  round-trips through the markdown frontmatter like the other person/org
  fields; only catalog values are accepted. Adopted from immoOS (#1031),
  where a GdWE legal form on a property's owner marks the property as
  WEG-divided — the fork drops its stopgap column with the next upstream
  merge (#1057).
- Rows in lists, trees and detail sections whose target is currently open as
  a card in the blade stack are highlighted in red, in addition to the spine
  chevron — a self-contained Stimulus controller watches the DOM; sidebar
  entries stay unchanged (#965, adopted from immoOS via #1057).
- `bin/rails gmail:setup` binds its OAuth loopback server to a fixed port
  when `GMAIL_SETUP_PORT` is set, so an SSH tunnel to a headless server can
  be established before starting the flow (#989, adopted from immoOS via
  #1057).
- Agent API bearer tokens are now stored only as SHA256 digests (like GitHub
  personal access tokens): a database leak no longer exposes usable tokens.
  Existing tokens keep working unchanged (they are hashed in place during
  migration); the plaintext is shown exactly once when an agent is created
  or its token is rotated — the agent settings page explains this and offers
  rotation if a token is lost (#1052).

- Two-factor authentication (TOTP) for the web login, opt-in per user: a new
  Settings → "Sicherheit" area enrolls an authenticator app via QR code,
  shows one-time recovery codes and lets you regenerate or disable the
  second factor; sign-in becomes two-step for enrolled users (password →
  code, with a 5-minute window), admins can reset a user's lost second
  factor from the user form, and both login steps are rate-limited
  (10 attempts / 3 minutes per IP) against brute force (#1051).

- List cards (tasks, notes, contacts, pinned, topics, tags, documents,
  invoices, communications, awaitings, inbox, history, time entries, sources,
  calendar, settings, dashboard) now carry the same card toolbar as detail
  cards — attach-to-dashboard, duplicate, reload, focus and close in one
  consistent icon row above the list header; the attach-to-dashboard button
  moves out of the individual list headers into the toolbar (#1049).

- When editing a template note (`vorlage:<type>` tag), the body editor shows
  a placeholder chip bar with the keys available for that template type —
  click copies the `{{placeholder}}` to the clipboard; document types add a
  hint that every info-block field is available under its label. Regular
  notes stay unchanged (#1036).
- Document and email templates get a visible management area (Settings →
  "Dokumentvorlagen"): templates are still regular notes tagged
  `vorlage:<type>` under the hood, but can now be created, opened and
  retired per type (letter, NDA, SEPA mandate, email) without knowing the
  tag convention; the area explains the `{{placeholder}}` mechanics and
  marks which template is active per document type. Email templates
  (`vorlage:email`) additionally appear as a picker in the "compose email"
  popover, prefilling subject ("Betreff:" first line) and body with
  `{{name}}`/`{{email}}`/`{{datum}}` resolved per recipient (#1036, #1027).
- On desktop, the close cross at the bottom of a card spine now opens a
  small menu instead of closing immediately: "close this card" or "close
  this card and all cards to its right" (disabled when the card is the
  rightmost). Closing several cards asks about unsaved drafts once across
  all of them; on mobile the cross keeps closing directly (#1032).
- Composing an email from a contact point no longer requires Gmail: a new
  per-user preference ("Compose email opens") picks between Gmail in the
  browser and the device's default mail app via `mailto:` — the automatic
  default uses Gmail only when the user's own Google account is connected.
  Email contact points additionally get a "compose with subject and text"
  popover that carries a prefilled subject and body into the draft; overlong
  mailto bodies fall back to the clipboard with a toast hint (#1027).
- Communication lists support batch editing like task lists: a multi-select
  toggle in the inbox card and the topic communications tab reveals per-row
  checkboxes and an action bar to assign the selected communications to a
  topic (additive) or delete them from miolimOS in one go (Gmail stays
  unchanged, with a confirmation prompt) (#1018).
- The card toolbar has a new `layers-plus` action that appends the card to the
  dashboard stack without navigating there — a toast confirms; the card shows
  up the next time the dashboard is opened. The action sits in every card
  head, not just the unified toolbar: list blades, settings pages and
  sub-pages, calendar, history, inbox, sources, time entries, tag lists,
  reference/render/properties blades and the tree-focus blade (#1005).
- Letters and outgoing invoices can be franked with a Deutsche Post
  Internetmarke printed straight into the DIN address field, so the letter
  goes into a window envelope with no separate stamp. A "Frankieren" block
  in the document blade buys the stamp via the Internetmarke REST API
  (per-user Portokasse/API credentials under Settings → Frankierung,
  secrets encrypted) or inserts a clearly marked dummy stamp for layout
  testing without an account (#995).
- Incoming invoices accept manually uploaded documents (PDF): an "upload
  document" button in the "Beleg" section attaches the original to invoices
  that were created manually instead of through the document import (#964).

### Changed

- The "duplicate card" icon in the card toolbar is now `copy-plus` instead of
  `copy`, so it is distinguishable from copy-to-clipboard actions (#1007).

### Fixed

- Buying a real Internetmarke no longer crashes after payment when the DHL
  API returns the voucher list as a plain array (one of its documented
  response shapes): the parser threw a TypeError and the paid voucher id was
  lost. Found by the new purchase-path tests, which now cover the login,
  both voucher response shapes, the wallet-empty error and the stamp
  download (#1055).
- Editing a task template no longer crashes with a 500: the edit link had
  been rendering an index view that was removed when settings moved into the
  blade stack (#613); editing now opens as a proper sub-blade (like users and
  agents), and validation failures redirect with an alert instead of hitting
  the missing view (#1054).
- Publishing a task draft with Ctrl+Shift+Enter while the title field still
  has focus no longer loses the freshly typed title: the publish request now
  carries the current title (like it already did for the description), and the
  server applies it before publishing (#1010).
- The tab row of a topic card no longer shows a vertical scrollbar: the active
  tab's underline overlap made the horizontally scrollable tab nav overflow by
  one pixel vertically; the separator line now lives on a wrapper so the tab
  links stay inside the scroll box (#998).
- The browser tab no longer reads "Wissen" when opening persons or organizations
  as a stack: the contacts list (sidebar "Personen" and the old `/contacts`
  redirect) titles the tab "Kontakte", and a person or organization opened as
  the first stack card titles it with its name (#982).
- On mobile, the horizontal card title bar (spine) keeps its content vertically
  centered: the footer buttons (history, close, draft pencil) no longer sit
  above the middle, and the bar grows with its content instead of pinning it to
  the top edge when the browser scales text (#950).
- Picking a task template no longer leaves its description invisibly stuck on
  the quick-add form: the selection now shows as a removable chip, and clearing
  the title (or removing the chip) discards the template description. Tasks
  typed without a template no longer silently carry the body of the last picked
  template (#966).
- Incoming invoices no longer offer time-entry assignment: the line blade hides
  the assigned/assignable times sections, the invoice card hides the time
  import, and the endpoints reject incoming invoices — billing own hours only
  applies to outgoing invoices (#968).
- VAT strings use a consistent section-sign notation with a non-breaking space
  ("§ 19 UStG" instead of "§19 UStG") in the German and English locales (#969,
  reported from immoOS).

## [0.3.2] - 2026-07-10

### Added

- Incoming invoices can be created manually from the invoice list — a third
  entry in the "new invoice" popover next to invoice/quote. The issuer picker
  offers all persons and organisations for incoming invoices (the issuer is an
  external party), instead of only own issuer companies (#946).
- Tasks show a backlinks section — knowledge items (notes, replies of other
  tasks) and other tasks whose description reference the task via a task
  wikilink. Task references are now recorded in the reference index; existing
  bodies were backfilled (#953).
- Task descriptions act as reference sources everywhere: their wikilinks to
  knowledge items appear in the backlinks panels and anchor popovers, and
  renaming a knowledge item rewrites title wikilinks in task descriptions too
  (#953).

### Changed

- Incoming invoices no longer carry a draft/final status or the PDF archiving
  lifecycle — no status field, no draft badge, no "archive current state". The
  artifact section is titled "Beleg" and holds the received original document
  (#946).

## [0.3.1] - 2026-07-09

### Added

- Person and organisation detail cards get a slim tab bar (master data ·
  communication) instead of one long vertical stack. The communication tab
  lists only the person's emails and appears only when there are any; the
  remaining backlinks (referencing items, tasks, awaitings) stay as a section
  in the master-data tab. People without linked data keep the flat layout
  (#849, adopted from immoos).

## [0.3.0] - 2026-07-09

### Added

- Invoices are a first-class entity with their own sidebar list, detail card
  and direction (outgoing/incoming). Outgoing invoices keep the number
  sequence and all rendering/e-invoice outputs; incoming invoices carry a due
  date, a payment status and the original PDF as a frozen artifact (#926,
  #934).
- Incoming-documents workflow: a new inbox processor analyses uploaded or
  mail-attached PDFs — ZUGFeRD/Factur-X e-invoices are read deterministically
  from the embedded EN 16931 XML (including payment terms), everything else is
  extracted by an LLM directly from the PDF with a schema-enforced JSON
  answer. A review step in the inbox card shows the extracted fields and
  selectable follow-up tasks before anything is persisted; deterministic
  e-invoices skip the review. Senders are matched via strong identifiers
  (VAT id, IBAN) before name matching and are created as organisation items
  with those identifiers when unknown (#934).
- Documents support `{{key}}` placeholders: values from the entity and its
  free info-block fields are merged into the body text before rendering;
  unresolved placeholders stay visible instead of silently disappearing, and
  the editor warns about them (#926).
- Scanned PDFs without a text layer get a searchable OCR copy on filing
  (requires the optional `ocrmypdf`/`tesseract-ocr-deu` packages; the step is
  skipped silently when they are missing) (#934).
- Documents without a mail context are matched against topics with the same
  embedding classifier used for e-mails; safe matches attach the topic
  automatically (#934).
- The dashboard shows a "task inbox" section for published tasks without a
  commitment (#930).
- Task spines show live status: WIP marker, done check, draft pencil and a
  focus highlight; list spines are unified and the collapse bar is easier to
  hit (#892, #893, #901, #902, #906, #913, #914, #919).
- Creating a document appends its card to the current stack instead of
  rebuilding a new one (#871).
- `simple_tabs` panels can persist the active tab across re-renders via an
  optional storage key (#915, adopted from the immoos fork).

### Changed

- The document model was split along "creation is a procedure, not an
  entity": `Document` now covers correspondence only (letter, NDA, SEPA
  mandate) while invoices/quotes live in the new `Invoice` entity. The shared
  machinery (parties, info-block fields, artifacts, lock, render/sign/archive)
  moved into a reusable printable layer that further entities can adopt
  (#926).
- Frozen PDF artifacts and free info-block fields are polymorphic and shared
  by all printable entities; the client portal lists artifacts of letters and
  invoices alike (#926).
- Persons and organisations no longer appear in a topic's knowledge list
  (#932).

### Fixed

- NDA PDFs lost their page margins because Chrome now prefers the theme's
  `@page { margin: 0 }` rule over print-call margins; the NDA layout sets its
  own `@page` override (#926).
- The sidebar collapse hid labels on mobile although the rail is
  desktop-only; collapse hiding is now guarded by the `md:` breakpoint
  (#856, adopted from the immoos fork).
- Newly created users received no default capabilities and hit
  "not allowed to read Task" on first login (#927, adopted from the immoos
  fork).
- Sender matching tolerates grouped IBANs ("DE89 3704 …") in master data, and
  the invoice number sequence ignores incoming invoices (#941).

### ⚠️ Upgrade notes

- The migration **deletes legacy invoice/quote documents** (`Document` rows of
  kind `rechnung`/`angebot` and their positions) instead of migrating them —
  they predate the new `Invoice` entity. Letters, NDAs and SEPA mandates are
  untouched.
- LLM extraction of incoming documents requires an Anthropic API key
  (`ANTHROPIC_API_KEY` or credentials); without it, only ZUGFeRD e-invoices
  are processed automatically.
- For OCR text layers install the optional packages:
  `apt install ocrmypdf tesseract-ocr-deu`.

## [0.2.1] - 2026-07-07

### Added

- A shared card toolbar gives every entity card the same connecting bar: the
  generic card actions (duplicate, reload, focus, close) live in one partial,
  and each card supplies its own entity-specific actions through a slot
  (#861, #868).
- Document cards carry their output actions (preview, PDF, ZUGFeRD, XRechnung,
  signed PDF, delete) as icons in the card toolbar instead of a text footer,
  with new Lucide-style icons for PDF, ZUGFeRD and the signed PDF plus an "XML"
  badge for XRechnung (#868).
- Pressing Tab in a task title now jumps straight into the description editor
  instead of stepping through the intervening controls (#867).
- A "close card" action is available at the right end of the card toolbar, in
  addition to the one on the spine (#861).

### Changed

- The publish/send action uses a paper-plane (send) icon instead of a globe
  across tasks, replies and knowledge items; the globe stays only for genuine
  web actions, and "complete contact data from a URL" now uses a user-search
  icon (#857, #858).
- Card toolbar icons are grouped consistently: entity actions on the left, card
  actions (duplicate/reload/focus/close) on the right (#863).
- The "revert to draft" icon is a neutral outline instead of a filled amber
  accent (#862).
- Sidebar: the scrollable area ends just above the bottom edge so the browser's
  native link preview can no longer cover an entry, the scrollbar is confined to
  the scrollable section, and the header, pinned items and settings entry stay
  fixed (#860, #875).
- The frame around the blade stack is half as wide (#877).
- The mobile top bar is decluttered — the timer and secondary icons are hidden
  on small screens (#857).

### Fixed

- Sidebar entries no longer shift vertically when the collapsed sidebar is
  expanded on hover, and all icons stay aligned on one vertical line (#859).
- Clicking into a text field of a partially visible stack card now scrolls the
  card fully into view, matching a click elsewhere in the card (#864).
- An invoice with no issuer selected no longer prints "miolim" in the
  letterhead; the header stays empty (#874).

## [0.2.0] - 2026-07-06

### Added

- First-run setup screen (#806): a fresh instance asks for the admin
  account in the browser instead of requiring `db:seed` + environment
  variables; `db:seed` now only loads optional example data.
- The stack history drawer (incl. pinned stacks) now syncs across devices:
  compositions live on the server per user, merged by final composition;
  localStorage remains a fast cache and offline fallback (#816).
- Configurable sidebar layout in the preferences (#846): the sidebar
  sections can be reordered and toggled per user, and the layout editor
  shows each section's icon.
- Person status is now shown on the main person icon (via its shape and
  colour) with a click menu to change it directly (#840).

### Changed

- Topic statuses reduced from four to two - active/inactive - since the
  three non-active statuses behaved identically; the topics list gains a
  "show inactive" filter and the topic type-ahead marks inactive topics
  while keeping them findable (#817). Migration maps old statuses to
  inactive.
- Generalization for self-hosters (#806): the research agent is
  configurable via `MIOLIMOS_RESEARCHER_EMAIL`, maintenance rake tasks use
  the instance's first human actor, Crossref/OpenLibrary user agents
  reference the project URL, and the default capability matrix lives in
  one place (`CapabilityDefaults`).
- Dependency refresh (first Dependabot batch, #805): puma 8.0.2,
  tailwindcss-rails 4.6, rubyzip 3.4.1, signet 0.22, google-apis gems,
  jbuilder 2.15.1, brakeman 8.0.5, thruster 0.1.22; GitHub Actions bumped
  (checkout v7, setup-node v6, docker actions). image_processing 2.0 no
  longer bundles a backend — `ruby-vips` is now declared explicitly.
- Popover menus can now be left-aligned and are clamped to the viewport so
  they no longer overflow the screen edge (#840).
- The dashboard icon changed from a house to a gauge (#843).

### Fixed

- A double-submit on the first-run setup no longer shows a 422 error page -
  the stale-token request now redirects to the login (#818).
- History view tracking now counts only the focused (active) stack card -
  previously every open card accumulated view time simultaneously, and even
  cleaning up a stack created history entries (#816). The first-ping retry
  after tab switches now actually happens.
- Agent pokes now send a safety Enter so prompts do not sit unsubmitted in
  the agent terminal when the first Enter lands mid-render (#815).
- Status messages from redirect flows ("topic created", ...) now appear as
  auto-dismissing toasts instead of static banners that never disappeared -
  especially noticeable on mobile (#809).
- Entity links inside stack cards now consistently open in the current
  stack instead of navigating away (#810): person-card backlinks (emails,
  awaitings), task chips (sources, knowledge, contacts), awaiting detail
  links (contact, task, triggering email), tasks-from-email links, and the
  topic marker on task rows.
- The accounts table now stays inside its card - the Google-Calendar target
  field no longer overflows it (#802).
- Adding or editing a person now expands a collapsed person section instead
  of appearing to do nothing (#845).
- Creating a person no longer flickers the form fields, and title/name
  handling is automatic (#827).

## [0.1.0] - 2026-07-03

First versioned, public baseline of miolimOS — the repository went public with
this release (fresh-start history; prior development lived in a private repo).

### Added

- Tasks, knowledge (Markdown notes with `[[wikilinks]]`), people &
  organizations, sources/citations, communications, time tracking,
  documents/invoices and a customer portal, in a stackable cards-in-a-stack UI.
- Bilingual (German/English) interface.
- Token-authenticated Operations API and optional autonomous agents.
- Optional integrations (Ollama email classification, Anthropic/OpenAI LLMs,
  Google Gmail/Calendar, audio/video transcription incl. speaker diarization,
  e-invoices, off-site backup) that all degrade gracefully when not configured.
- Version & release management: a `VERSION` file as the single source of truth,
  `Miolimos::VERSION` exposed in code, the version shown in the Settings footer,
  this changelog, an upgrade guide, and a documented release process (#745).
- Test coverage for previously untested live paths: task/knowledge replies,
  communication tags, settings templates, stack history resolve, and the
  Gmail send path (#801).
- JavaScript unit tests (`node --test test/javascript/*.test.js`, no build
  step) for the blade-stack routing table and history persistence; JS tests
  and the Cuprite system tests now run as separate CI jobs (#801).

### Changed

- Contact enrichment from a URL (#761) extracted from the controller into the
  `ContactEnrichment` service; behaviour unchanged (#801).
- Size refactorings, behaviour unchanged (#803): topic tab-list loading moved
  into the `TopicListLoading` concern; the wikilink resolver split into
  per-phase helpers; the knowledge-item detail view cut into section partials;
  edit-mode, mobile-layout and card-resize logic extracted from
  `blade_stack_controller.js` into lib mixins.

### Fixed

- Two Ruby deprecation warnings: a frozen-string mutation in the wikilink
  renderer and a `JSON.generate` encoding warning (binary Gmail bodies) that
  would raise with json 3.0 (#801).

[Unreleased]: https://github.com/miolim/miolimos/compare/v0.3.5...HEAD
[0.3.5]: https://github.com/miolim/miolimos/compare/v0.3.4...v0.3.5
[0.3.4]: https://github.com/miolim/miolimos/compare/v0.3.3...v0.3.4
[0.3.3]: https://github.com/miolim/miolimos/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/miolim/miolimos/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/miolim/miolimos/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/miolim/miolimos/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/miolim/miolimos/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/miolim/miolimos/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/miolim/miolimos/releases/tag/v0.1.0
