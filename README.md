# miolimOS

miolimOS is a personal knowledge-and-work operating system: a single,
keyboard-driven workspace that ties together tasks, knowledge (Markdown
notes with wikilinks), people & organizations, sources/citations,
communications, time tracking, documents/invoices and a customer portal —
built around a stackable "cards in a stack" interface.

Built with **Ruby on Rails 8.1**, PostgreSQL, Hotwire (Turbo + Stimulus)
and Tailwind, using importmaps (**no JavaScript build step**) and
Solid Queue/Cache/Cable (no Redis required).

> **Status:** miolimOS is actively developed and was originally tailored to
> its author's setup. A broader, self-hostable release is being prepared;
> some operational pieces are still being generalized. The UI is fully
> bilingual (German/English).

---

## Requirements

- **Ruby 3.4.8** (see `.ruby-version`)
- **PostgreSQL** 14+
- A C toolchain + `libvips` (image processing) and `libpq` (Postgres client)

Optional, only for specific features (all degrade gracefully if absent —
see [External services](#external-services)):
Ollama, Anthropic/OpenAI API keys, Google (Gmail/Calendar) OAuth credentials,
`yt-dlp`, `rclone`, Chrome/Chromium (document PDFs, system tests),
Node.js 20+ (JS unit tests, development only).

## Quick start (local)

```bash
git clone https://github.com/miolim/miolimos.git
cd miolimos

# 1. Credentials: the repo ships no credentials file (it is gitignored).
#    Generate your own (this creates config/master.key + credentials.yml.enc):
bin/rails credentials:edit   # opens an editor; save & close to generate

# 2. Configure environment (optional — sensible defaults exist):
cp .env.example .env         # then edit as needed

# 3. Install deps, create & migrate the database, start the dev server:
bin/setup
```

`bin/setup` runs `bundle install`, `bin/rails db:prepare`, and then starts
the dev server via `bin/dev` (Rails server + Tailwind watcher on
`http://localhost:3000`).

On first visit, miolimOS shows a **first-run setup screen** that creates
the admin account — no seeding or environment variables required. The
screen disappears permanently once a user exists.

To additionally load example data (demo topics, tasks, notes):

```bash
bin/rails db:seed
```

### Run with Docker

A production `Dockerfile` ships with the app, and a `compose.yaml` brings up
the app together with PostgreSQL:

```bash
# Provide your master key + a DB password, then:
RAILS_MASTER_KEY=$(cat config/master.key) docker compose up --build
```

See [compose.yaml](compose.yaml) for the configurable environment variables.

## Running the tests

```bash
bin/rails test                        # ~1600 tests (models, services, web)
bin/rails test:system                 # browser tests (headless Chromium via Cuprite)
node --test test/javascript/*.test.js # JS unit tests (or: npm test)
bin/rubocop                           # style (rubocop-rails-omakase)
bin/brakeman                          # security scan
```

CI runs all of these on every push/PR (see `.github/workflows/ci.yml`).

## Upgrading

miolimOS follows [Semantic Versioning](https://semver.org/); the current
version is shown in the **Settings** footer and stored in the `VERSION` file.
To move an existing instance to a newer version:

```bash
git pull            # or: docker compose pull
bundle install      # Git checkout only; the Docker image bundles deps
bin/rails db:migrate
bin/deploy          # or: docker compose up -d
```

**Back up the database first** — migrations can be irreversible. See
**[UPGRADING.md](UPGRADING.md)** for the full procedure and
**[CHANGELOG.md](CHANGELOG.md)** for what changed in each version. Maintainers:
see **[docs/releasing.md](docs/releasing.md)** for the release process.

## Configuration

All runtime configuration is via environment variables with safe defaults;
see **[.env.example](.env.example)**. The most relevant:

| Variable | Default | Purpose |
| --- | --- | --- |
| `MIOLIMOS_HOST` | `os.miolim.de` | Public hostname (mailer links, websocket origin) |
| `MIOLIMOS_PROTOCOL` | `https` | Protocol for generated URLs |
| `MIOLIMOS_DB_HOST` | `localhost` | PostgreSQL host (production) |
| `MIOLIMOS_SRC_DATABASE_PASSWORD` | — | PostgreSQL password (production) |
| `MIOLIMOS_ADMIN_EMAIL` / `_PASSWORD` | `admin@example.com` / random | Seed admin |

### External services

These integrations are **optional**; miolimOS boots and its core features
work without any of them. Configure them only for the corresponding
feature:

| Feature | Needs | Without it |
| --- | --- | --- |
| Inbox AI (transforms, summaries, tags) | `ANTHROPIC_API_KEY` (or local Ollama) | AI-assisted inbox steps unavailable |
| Email classifier | Ollama + `bge-m3` (see [docs/ollama-setup.md](docs/ollama-setup.md)) | Classification is skipped silently |
| Email send/sync, Calendar | Google OAuth credentials (`google.*` in Rails credentials) | Email/calendar sync disabled |
| Audio/video transcription | `OPENAI_API_KEY`, `yt-dlp` | Transcription unavailable |
| Speaker recognition (diarization) | `ASSEMBLYAI_API_KEY` | Only plain Whisper transcription offered |
| Document PDFs (letters, invoices) | Chrome/Chromium (`CHROME_BIN`) | PDF rendering unavailable |
| E-invoices (ZUGFeRD/XRechnung) | Python venv with drafthorse + factur-x (`ZUGFERD_PYTHON`) | Plain PDF invoices only |
| Off-site DB backup | `rclone` (see `ops/backup/`) | Local backups only |

## Architecture (at a glance)

- **Cards & stacks:** every entity (task, knowledge item, person, source,
  document, …) renders as a *card*; cards live in horizontally-scrollable
  *stacks*. The frontend is Turbo + Stimulus, no SPA framework.
- **Knowledge** is Markdown with `[[wikilinks]]`; the database is the source
  of truth, files are an export.
- **Background work** runs on Solid Queue; caching on Solid Cache; live
  updates on Solid Cable — all Postgres-backed (no Redis).
- **Customer portal** is a separate, outward-facing mini-app under `/portal`
  with its own magic-link auth.
- **Agents** (optional): autonomous assistants drive miolimOS through the
  same token-authenticated Operations API a human uses. See
  [docs/agents.md](docs/agents.md).

## Contributing

miolimOS uses a **maintainer-driven contribution model**: the most useful
way to contribute is a clearly described feature request or "user story"
that the maintainer implements, rather than a code pull request. Please read
**[CONTRIBUTING.md](CONTRIBUTING.md)** before opening a PR. Code
contributions require signing the **[Contributor License Agreement](CLA.md)**.

## License

miolimOS is licensed under the **GNU Affero General Public License v3.0**
(AGPL-3.0) — see [LICENSE](LICENSE). You are free to use, study, modify, run
and self-host it; if you run a **modified** version as a network service, the
AGPL requires you to make your modified source available to its users. The
copyright holder additionally reserves the right to offer miolimOS under
separate commercial terms (this is what the CLA enables).

Copyright © Hans Siem Groth. "miolimOS" is the name of this project; please do
not use it for substantially modified forks without permission.
