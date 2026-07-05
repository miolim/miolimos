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

- First-run setup screen (#806): a fresh instance asks for the admin
  account in the browser instead of requiring `db:seed` + environment
  variables; `db:seed` now only loads optional example data.

### Fixed

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

[Unreleased]: https://github.com/miolim/miolimos/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/miolim/miolimos/releases/tag/v0.1.0
