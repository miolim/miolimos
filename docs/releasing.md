# Releasing miolimOS

miolimOS uses [Semantic Versioning](https://semver.org/). The `VERSION` file at
the repo root is the single source of truth; `Miolimos::VERSION` reads it and
the Settings footer displays it.

> **Pre-public note:** until the repository is public, the version machinery is
> in place but no real release is cut. The first tag (`v0.1.0`) is created once
> the open #735 pre-public checklist (history scrub, admin-password rotation,
> …) is done. Until then, keep the `Unreleased` changelog section up to date.

## Keep the changelog current

Whenever a change lands on `main` that users would notice, add a bullet to the
**`## [Unreleased]`** section of [CHANGELOG.md](../CHANGELOG.md) under the right
heading (`Added` / `Changed` / `Fixed` / `Removed` / `Deprecated` / `Security`).
Note breaking changes and any operator action under **⚠️ Upgrade notes**.

## Cutting a release

1. **Pick the version.** Bump per SemVer: breaking → minor while `0.x`
   (`0.1 → 0.2`), otherwise patch (`0.1.0 → 0.1.1`).
2. **Update `VERSION`** to the new number.
3. **Update the changelog:** rename `## [Unreleased]` to
   `## [X.Y.Z] - YYYY-MM-DD`, start a fresh empty `Unreleased` above it, and fix
   up the compare/tag link references at the bottom.
4. **Commit** on `main`: `chore(release): vX.Y.Z`.
5. **Tag** the commit: `git tag -a vX.Y.Z -m "vX.Y.Z"` and push the tag
   (`git push origin vX.Y.Z`).
6. **GitHub release:** create a release for the tag, pasting that version's
   changelog section as the notes.

## Tagged Docker images (CI)

Pushing a `v*` tag triggers
[`.github/workflows/release.yml`](../.github/workflows/release.yml), which
builds the production image and pushes it to the GitHub Container Registry
(`ghcr.io`) tagged with both `X.Y.Z` and `latest`. No extra secrets are
required — it authenticates with the built-in `GITHUB_TOKEN`. Operators pull
with:

```bash
docker pull ghcr.io/miolim/miolimos:0.1.0
```

This step is optional infrastructure: a release is valid (tag + GitHub release)
even if image publishing is disabled.
