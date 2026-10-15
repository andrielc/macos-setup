# kernel-repo

Target directory for the **Android GKI (Generic Kernel Image)** kernel source.

Populated by [`../scripts/kernel-sync.sh`](../scripts/kernel-sync.sh), which uses
the AOSP `repo` tool to init + sync the newest GKI release branch here. The synced
source is **git-ignored** (it's several GB) — only this README and `.gitkeep`
are tracked.

## Sync it

```bash
# From the repo root:
./scripts/kernel-sync.sh                 # newest common-androidNN-X.Y (full)
./scripts/kernel-sync.sh -b common-android-mainline   # dev branch tracking upstream
./scripts/kernel-sync.sh --shallow       # --depth=1, much smaller/faster, no history
./scripts/kernel-sync.sh -b common-android15-6.6   # a specific GKI release
```

- Default branch: the newest `common-androidNN-X.Y` release branch, resolved at
  run time (`common-android18-7.4` as of 2026-10). `-j` defaults to min(cores, 8).
- Default destination: this folder.
- Re-running resumes an interrupted sync.

List all GKI branches:

```bash
git ls-remote --heads https://android.googlesource.com/kernel/manifest \
  | sed 's#.*refs/heads/##' | grep common-android
```

## After sync

Kernel source lands under `common/`. Build with Kleaf (modern) or the legacy
`build/build.sh` — see the hints printed at the end of the sync script.
