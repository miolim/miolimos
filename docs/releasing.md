# Releasing miolimOS

miolimOS uses [Semantic Versioning](https://semver.org/). The `VERSION` file at
the repo root is the single source of truth; `Miolimos::VERSION` reads it and
the Settings footer displays it.

> **History note:** the repository is public (`github.com/miolim/miolimos`) and
> the first tag `v0.1.0` was cut after the #735 pre-public checklist (history
> scrub, admin-password rotation, …). Releases are cut on the public
> `public-main` branch — see [Publishing to the public mirror](#publishing-to-the-public-mirror).

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

## Publishing to the public mirror

Development happens in the private repo (`origin`,
`github.com/Rabisnah/miolimos_src`) on `main`. The public repository
(`github.com/miolim/miolimos`, remote `public`) is served by a **separate,
curated branch, `public-main`** — an *orphan* branch with no common ancestor
with `main`. Publishing is therefore **not** a merge or a `main → public` push;
it is a deliberate replay of new `main` commits onto `public-main`.

There is no automated tooling for this — it is done by hand, per publish:

1. **Sensitive-path check (safety gate).** There is no per-commit scrub, so
   every change on `main` becomes public verbatim. Before replaying, inspect
   what would go out:

   ```bash
   git diff --name-status public-main..main
   ```

   Confirm nothing sensitive is in the set — `config/credentials*`, `.env*`,
   `db/seeds*` with real data, `ops/*` secrets. (`config/credentials.yml.enc`,
   `.env*` and `.claude/` are already untracked/gitignored since the #735
   pre-public scrub, so they never appear here.)
2. **Replay the new commits.** Cherry-pick the commits that are on `main` but
   not yet on `public-main`, in order, onto `public-main`. The trees are
   otherwise identical, so they apply cleanly; keep each task as its own commit
   (do **not** squash). Rewrite an internal commit subject to a public-facing
   wording where needed, and split/regroup commits if the private grouping is
   awkward.
3. **Verify equivalence.** For each replayed pair, `git patch-id --stable`
   should match between the `main` commit and its `public-main` replay.
4. **Never touch `signatures/cla.json`.** It is created by the CLA-assistant bot
   and exists **only** on `public-main`. Do not delete it during a replay and
   never merge it back into `main`.
5. **Push and tag.** Push `public-main` to `public` (`git push public
   public-main:main`). For a real release, the version bump + changelog commit
   from *Cutting a release* is one of the replayed commits; tag it on
   `public-main` and push the tag to `public` (`git push public vX.Y.Z`) — this
   is the tag the CI image build and the GitHub release attach to. (The private
   `origin` does not carry release tags; the public history is authoritative for
   releases.)

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
