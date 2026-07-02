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
