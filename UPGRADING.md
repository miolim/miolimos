# Upgrading miolimOS

This guide describes how to move a running miolimOS instance to a newer
version. For *what* changed in each version, see [CHANGELOG.md](CHANGELOG.md).

## Versioning

miolimOS follows [Semantic Versioning](https://semver.org/). While the major
version is `0`, treat **minor** bumps (`0.1 → 0.2`) as potentially
breaking — read the changelog entry before upgrading. The current version is
shown in the **Settings** footer and stored in the `VERSION` file.

## General upgrade procedure

The same steps apply whether you run from a Git checkout or via Docker; pick
the matching first step.

```bash
# 1a. Git checkout:
git pull

# 1b. …or Docker:
docker compose pull            # or: docker pull ghcr.io/miolim/miolimos:<tag>

# 2. Update dependencies (Git checkout only — the image bundles these):
bundle install

# 3. Apply database migrations:
bin/rails db:migrate           # Docker: docker compose run --rm web bin/rails db:migrate

# 4. Restart the app:
#    Git/Kamal: bin/deploy        Docker: docker compose up -d
```

There is **no JavaScript build step** (importmaps); a `git pull` is enough for
front-end changes. Assets are precompiled at boot/deploy as usual.

## Before you upgrade

- **Back up the database** (`pg_dump`) — migrations can be destructive and are
  not automatically reversible.
- Skim the [CHANGELOG.md](CHANGELOG.md) entries between your version and the
  target version, in particular any **Breaking changes** note.

## Sensitive migrations

When a release contains a migration that needs operator attention (data
backfill, a column drop that cannot be rolled back, a required new environment
variable, downtime), it is called out explicitly in the changelog under a
**⚠️ Upgrade notes** heading for that version. Always read those before running
`db:migrate` in production. When in doubt, run the migration against a copy of
the production database first.

## Rolling back

Code can be rolled back by checking out the previous tag (or pulling the
previous image). **Database migrations cannot always be rolled back** — this is
why step 0 is a backup. If a release's changelog marks a migration as
irreversible, a downgrade requires restoring the pre-upgrade database dump.
