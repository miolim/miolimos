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

[Unreleased]: https://github.com/miolim/miolimos/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/miolim/miolimos/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/miolim/miolimos/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/miolim/miolimos/releases/tag/v0.1.0
