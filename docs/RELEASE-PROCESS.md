# Release Process

Canonical release process for **Space-Tag-CLI** (the OSS CLI + configs) and how
the closed-source **SpaceTag** app consumes a release.

> This file lives in `notTag/Space-Tag-CLI` at `docs/RELEASE-PROCESS.md` and is
> symlinked into the SpaceTag repo as `RELEASE-PROCESS.md`. Edit it here — both
> repos read the same source of truth.

Decoupled cadence: Space-Tag-CLI tags on its own schedule; SpaceTag bumps its pin
when ready. See `DISTRIBUTION.md` (SpaceTag repo) for the full bundle/sign/notarize
pipeline this slots into.

---

## Versioning

Semver, by config/contract impact on the consuming app:

| Bump | Meaning |
|---|---|
| MAJOR | breaking config or contract change SpaceTag must adapt to |
| MINOR | additive (new config, backward-compatible) |
| PATCH | fixes only |

The artifact is **configs + glue only** — `sketchybar/`, `yabai/`, `zsh/`. Binaries
(yabai, sketchybar, jq) are pinned and sourced separately by SpaceTag.

---

## Part 1 — Cut a Space-Tag-CLI release (this repo)

1. Land all changes on the default branch; confirm `sketchybar/ yabai/ zsh/` are in
   the state you want shipped.
2. Tag and push:
   ```bash
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```
3. The `release` workflow (`.github/workflows/release.yml`) fires on `v*` and:
   - packs `space-tag-cli-X.Y.Z.tar.gz` (`tar czf … sketchybar yabai zsh`)
   - writes `space-tag-cli-X.Y.Z.tar.gz.sha256` (`sha256sum`)
   - publishes a GitHub Release with both assets (`gh release create … --generate-notes`)
4. Verify the Release page shows the tarball **and** its `.sha256`. Note the
   checksum — SpaceTag pins it next.

No manual packaging: the tag is the trigger, the workflow is the publisher.

---

## Part 2 — Update SpaceTag with the release

In the **SpaceTag** repo (`space-tag-app`):

1. Edit `space-tag-cli.lock`:
   ```sh
   SPACE_TAG_CLI_VERSION=X.Y.Z
   SPACE_TAG_CLI_SHA256=<sha256 from the release's .sha256 asset>
   ```
   This single committed change is the update mechanism — open it as a reviewable PR.
2. `Scripts/vendor.sh` reads the lock and stages configs into `Resources/config/`:
   - `gh release download vX.Y.Z -R notTag/Space-Tag-CLI` the tarball + `.sha256`
   - **two-stage verify** — the release's own `.sha256`, then the audited
     `SPACE_TAG_CLI_SHA256` from the lock. Mismatch = fail closed, nothing staged.
   - Fallback: while the lock is unpinned (`SPACE_TAG_CLI_SHA256=PENDING_FIRST_RELEASE`)
     or `SPACE_TAG_CLI_SOURCE=local`, it uses the `vendor/space-tag-cli` submodule
     instead (dev loop).
3. `Scripts/build.sh [release]` runs `vendor.sh` if needed, `swift build`, and
   assembles `dist/SpaceTag.app` with `Resources/{bin,config,fonts}`.
4. For paid distribution, continue with sign → notarize → staple → DMG
   (`DISTRIBUTION.md` §4).

---

## Flow

```
Space-Tag-CLI:  commit → tag vX.Y.Z → CI publishes tarball + sha256
        │  (decoupled — own cadence)
        ▼
SpaceTag:  edit space-tag-cli.lock (version + sha256) → PR → review
        → vendor.sh fetch + 2-stage verify → build.sh assemble
        → sign → notarize → staple → DMG → ship
```

---

## First release (bootstrap)

SpaceTag's lock currently ships `SPACE_TAG_CLI_VERSION=0.0.0` /
`SPACE_TAG_CLI_SHA256=PENDING_FIRST_RELEASE`, so `vendor.sh` is on the submodule
fallback. To switch onto the verified release path:

1. Cut `v0.1.0` here (Part 1).
2. Copy the published sha256 into `space-tag-cli.lock` and set the version (Part 2).

After that, every config change ships as a normal tagged release + lock bump.
