#!/usr/bin/env bash
# scripts/kernel-sync.sh — download the Android GKI (Generic Kernel Image)
# kernel source into ./kernel-repo using the AOSP `repo` tool.
#
# Default branch: "latest" = the newest GKI release branch in the manifest
# (common-androidNN-X.Y, resolved at run time; common-android18-7.4 as of
# 2026-10). Use -b common-android-mainline for the dev branch that tracks
# upstream Linux. List others with:
#   git ls-remote --heads https://android.googlesource.com/kernel/manifest
#
# Usage:
#   scripts/kernel-sync.sh                  # newest GKI release into ./kernel-repo
#   scripts/kernel-sync.sh -b common-android-mainline
#   scripts/kernel-sync.sh -b common-android15-6.6
#   scripts/kernel-sync.sh -d ~/kernel-repo # custom destination
#   scripts/kernel-sync.sh --shallow        # --depth=1, no history (smaller/faster)
#   scripts/kernel-sync.sh -j 8             # parallel jobs
#   scripts/kernel-sync.sh --dry-run
#
# Heads-up: a full sync is several GB and can take a while. --shallow
# reduces it substantially but drops git history.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

MANIFEST_URL="https://android.googlesource.com/kernel/manifest"
BRANCH="latest"
DEST="$REPO_ROOT/kernel-repo"
# Capped at 8: googlesource.com throttles (HTTP 429) aggressive parallel
# fetches, and more jobs than that buys little. Override with -j.
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
(( JOBS > 8 )) && JOBS=8
SHALLOW=0
export DRY_RUN="${DRY_RUN:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--branch)  shift; BRANCH="${1:-}" ;;
    -d|--dest)    shift; DEST="${1:-}" ;;
    -j|--jobs)    shift; JOBS="${1:-}" ;;
    --shallow)    SHALLOW=1 ;;
    --dry-run)    DRY_RUN=1 ;;
    -h|--help)    sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) err "unknown arg: $1"; exit 1 ;;
  esac
  shift || true
done

# Resolve "latest" to the newest release branch (version-sorted, so
# android18 > android17 and 7.4 > 6.18).
if [[ "$BRANCH" == "latest" ]]; then
  BRANCH="$(git ls-remote --heads "$MANIFEST_URL" 2>/dev/null \
    | sed 's#.*refs/heads/##' | grep -E '^common-android[0-9]+-[0-9]+\.[0-9]+$' \
    | sort -V | tail -1)"
  [[ -n "$BRANCH" ]] || { err "could not resolve the latest GKI branch (network?) — pass -b"; exit 1; }
fi

step "Android GKI kernel sync"
info "branch:   $BRANCH"
info "dest:     $DEST"
info "jobs:     $JOBS"
info "manifest: $MANIFEST_URL"
[[ "$SHALLOW" == "1" ]] && info "mode:     shallow (--depth=1, no history)"

# ── Locate the `repo` tool ──────────────────────────────────────────
REPO_BIN=""
for c in "$(command -v repo 2>/dev/null || true)" "$HOME/.bin/repo"; do
  [[ -n "$c" && -x "$c" ]] && { REPO_BIN="$c"; break; }
done
if [[ -z "$REPO_BIN" ]]; then
  err "'repo' not found. Install it:  brew install repo"
  err "(or: curl https://storage.googleapis.com/git-repo-downloads/repo > ~/.bin/repo && chmod +x ~/.bin/repo)"
  exit 1
fi
info "repo:     $REPO_BIN"

command -v git >/dev/null || { err "git not found (install Xcode CLT)"; exit 1; }
command -v python3 >/dev/null || { err "python3 not found (repo needs it)"; exit 1; }

# ── Confirm the branch exists before doing anything heavy ───────────
if ! git ls-remote --exit-code --heads "$MANIFEST_URL" "$BRANCH" >/dev/null 2>&1; then
  err "branch '$BRANCH' not found in the kernel manifest."
  err "List available branches with:"
  err "  git ls-remote --heads $MANIFEST_URL | sed 's#.*refs/heads/##'"
  exit 1
fi
ok "branch '$BRANCH' exists"

run mkdir -p "$DEST"

# ── Refuse a case-insensitive destination ───────────────────────────
# The kernel tree has case-colliding paths (e.g. net/netfilter/xt_TCPMSS.c
# vs xt_tcpmss.c). On a case-INsensitive volume — the macOS default — git
# silently keeps only one of each pair, corrupting the checkout. Probe the
# destination directly (no dependency on diskutil output formats).
if [[ "$DRY_RUN" != "1" ]]; then
  probe="$DEST/.casecheck.$$"
  : > "${probe}A" 2>/dev/null || true
  if [[ -e "${probe}a" ]]; then
    rm -f "${probe}A" "${probe}a"
    # Discover the APFS container backing the destination so the hint is
    # correct for THIS machine (hardcoding e.g. disk3 is wrong elsewhere).
    # diskutil won't take an arbitrary subdir, so resolve the volume's mount
    # point via df first, then read the container off that.
    mp="$(df -P "$DEST" 2>/dev/null | awk 'NR==2{print $NF}')"
    container="$(diskutil info "${mp:-/}" 2>/dev/null \
      | awk -F': +' '/^[[:space:]]*APFS Container:/{print $2; exit}')"
    [[ -n "$container" ]] || container="diskX   # find it with: diskutil list"
    err "destination is on a CASE-INSENSITIVE volume: $DEST"
    err "The GKI tree has case-colliding paths; git would clobber files there."
    err "The default destination (./kernel-repo) is on the boot volume, which"
    err "is case-insensitive on stock macOS — so this guard trips by default."
    err "Create a case-sensitive APFS volume and sync into it with -d, e.g.:"
    err "  diskutil apfs addVolume $container 'Case-sensitive APFS' kernel-cs"
    err "  ./scripts/kernel-sync.sh -d /Volumes/kernel-cs/kernel-repo"
    exit 1
  fi
  rm -f "${probe}A"
fi

# ── repo init ───────────────────────────────────────────────────────
INIT_ARGS=(init -u "$MANIFEST_URL" -b "$BRANCH")
[[ "$SHALLOW" == "1" ]] && INIT_ARGS+=(--depth=1)
info "repo ${INIT_ARGS[*]}"
if [[ "$DRY_RUN" == "1" ]]; then
  info "(dry-run) would run the above in $DEST"
else
  ( cd "$DEST" && "$REPO_BIN" "${INIT_ARGS[@]}" ) || { err "repo init failed"; exit 1; }
fi

# ── repo sync ───────────────────────────────────────────────────────
# -c : current branch only   -q : quieter   --no-tags : smaller
SYNC_ARGS=(sync -c -j"$JOBS" --no-tags --optimized-fetch --force-sync)
info "repo ${SYNC_ARGS[*]}"
if [[ "$DRY_RUN" == "1" ]]; then
  info "(dry-run) would sync into $DEST (several GB; shallow is smaller)"
  exit 0
fi

( cd "$DEST" && "$REPO_BIN" "${SYNC_ARGS[@]}" ) || { err "repo sync failed (re-run to resume)"; exit 1; }

ok "GKI kernel '$BRANCH' synced into $DEST"
info "Source is under $DEST/common (and prebuilt toolchains alongside)."
warn "Building GKI needs a Linux x86_64 host — the Kleaf/build.sh toolchains"
warn "are linux-x86 prebuilts and do NOT run on macOS. Sync/read here, build"
warn "on Linux (VM, container, or remote), e.g.:"
cat <<EOF
  cd "$DEST"
  # Kleaf (modern):   tools/bazel build //common:kernel_aarch64
  # Legacy build.sh:  BUILD_CONFIG=common/build.config.gki.aarch64 build/build.sh
EOF
