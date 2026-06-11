# Release Process

Canonical release process for **Space-Tag-CLI** (the OSS CLI + configs) and how the
closed-source **SpaceTag** app consumes a release.

> This file lives in `notTag/Space-Tag-CLI` at `docs/RELEASE-PROCESS.md` and is
> symlinked into the SpaceTag repo as `RELEASE-PROCESS.md`. Edit it here — both
> repos read the same source of truth.

Decoupled cadence: Space-Tag-CLI tags on its own schedule; SpaceTag bumps its pin
when ready. See `DISTRIBUTION.md` (SpaceTag repo) for the full bundle/sign/notarize
pipeline this slots into.

One tag on the CLI repo drives **both** the published Release tarball **and** the
`vendor/space-labels` submodule pointer. `Scripts/repin.sh` is the only bridge — it
pins both in lockstep. **Never hand-edit `space-tag-cli.lock`.**

---

## Versioning

Semver, by config/contract impact on the consuming app:

| Bump | Meaning |
|---|---|
| MAJOR | breaking config or contract change SpaceTag must adapt to |
| MINOR | additive (new config, backward-compatible) |
| PATCH | fixes only |

Artifact is **configs + glue only** — `sketchybar/`, `yabai/`, `bin/`, `shell/`. Binaries
(yabai, sketchybar, jq) are pinned and sourced separately by SpaceTag.

---

## Part 1 — Cut a Space-Tag-CLI release (this repo)

1. Land all changes on the default branch; confirm `sketchybar/ yabai/ bin/ shell/` are ship-ready.
2. `git tag vX.Y.Z && git push origin vX.Y.Z`.
3. The `release` workflow (`.github/workflows/release.yml`) fires on `v*`: packs
   `space-tag-cli-X.Y.Z.tar.gz`, writes its `.sha256`, and publishes a GitHub Release with both assets.
4. Confirm the Release page shows the tarball **and** its `.sha256`.

The tag is the trigger; the workflow is the publisher — no manual packaging.

---

## Part 2 — Repin SpaceTag (`space-tag-app` repo)

1. New branch; keep `space-tag-cli.lock` + `vendor/space-labels` clean (commit/stash other edits first — `repin.sh` refuses a dirty pin).
2. `Scripts/repin.sh X.Y.Z` (or `--latest`) — downloads + verifies the tarball, rewrites the lock (sha computed from the verified download), runs `vendor.sh` (configs only) to re-verify, bumps `vendor/space-labels` to `vX.Y.Z`, and **stages** (never commits).
3. Review the staged diff (`space-tag-cli.lock` + submodule gitlink) → commit → PR → merge.
4. `Scripts/build.sh [release]` — auto-runs `vendor.sh`, `swift build`, assembles `dist/SpaceTag.app`.
5. Paid distribution: sign → notarize → staple → DMG (`DISTRIBUTION.md` §4).

---

## Flow

```
Space-Tag-CLI:  commit → tag vX.Y.Z → CI publishes tarball + sha256
        │  (decoupled — own cadence)
        ▼
SpaceTag:  Scripts/repin.sh X.Y.Z  (lock + submodule, verified) → review → commit → PR
        → build.sh assemble → sign → notarize → staple → DMG → ship
```

---

## Gotchas

- **Merging to `main` is not enough.** `repin.sh` pulls a *published Release tag*, not `main`. Part 1 must finish first, or step 2 aborts with `release vX.Y.Z not found`.
- **No prerequisite scripts before `repin.sh`.** It runs `vendor.sh` itself (configs only, `VENDOR_SKIP_BINARIES=1`). Do not pre-run `vendor.sh` or `build.sh`.
- **`repin.sh` fails closed.** Missing release/asset, checksum mismatch, missing matching submodule tag, or a dirty pin → clean abort, nothing staged, mutations rolled back.
- **Lock + submodule move together.** That lockstep is the whole point; hand-editing the lock breaks it.

> Bootstrap is done: the lock is pinned to a real release (`SPACE_TAG_CLI_VERSION` +
> `SPACE_TAG_CLI_SHA256`), so `vendor.sh` is on the verified release path. The
> submodule fallback only applies if a lock is reset to `PENDING_FIRST_RELEASE` or
> `SPACE_TAG_CLI_SOURCE=local` is set for a dev loop.
