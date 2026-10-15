#!/usr/bin/env bash
# scripts/v8-sync.sh — download (and optionally build) the V8 JavaScript
# engine with Chromium's depot_tools, plus the Fuzzilli JS fuzzer.
#
# Layout (defaults):  ~/tools/depot_tools   ~/tools/v8/.gclient   ~/tools/v8/v8
#                     ~/tools/fuzzilli      (cloned via tools-sync.sh)
#
# Usage:
#   scripts/v8-sync.sh                    # fetch / update V8 (origin/main)
#   scripts/v8-sync.sh -r origin/14.2-lkgr  # sync a specific ref/branch/commit
#   scripts/v8-sync.sh --shallow          # first fetch with --no-history (smaller)
#   scripts/v8-sync.sh -d ~/src/v8        # custom gclient workdir
#   scripts/v8-sync.sh --build            # + release d8   -> v8/out/<cpu>.release
#   scripts/v8-sync.sh --fuzzbuild        # + Fuzzilli-instrumented d8 -> v8/out/fuzzbuild
#   scripts/v8-sync.sh --fuzzilli         # --fuzzbuild + clone & build Fuzzilli
#   scripts/v8-sync.sh -j 8 --dry-run
#
# Sync works with just the Command Line Tools; BUILDING needs full Xcode
# (Chromium's mac toolchain uses the Xcode SDK). Unlike the kernel tree, V8
# is fine on the default case-insensitive APFS volume.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

DEPOT_TOOLS="${DEPOT_TOOLS:-$HOME/tools/depot_tools}"
DEPOT_URL="https://chromium.googlesource.com/chromium/tools/depot_tools.git"
FUZZILLI_DIR="$HOME/tools/fuzzilli"
DEST="$HOME/tools/v8"
REF="origin/main"
JOBS=""
SHALLOW=0; BUILD=0; FUZZBUILD=0; FUZZILLI=0
export DRY_RUN="${DRY_RUN:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dest)    shift; DEST="${1:-}" ;;
    -r|--ref)     shift; REF="${1:-}" ;;
    -j|--jobs)    shift; JOBS="${1:-}" ;;
    --shallow)    SHALLOW=1 ;;
    --build)      BUILD=1 ;;
    --fuzzbuild)  FUZZBUILD=1 ;;
    --fuzzilli)   FUZZILLI=1; FUZZBUILD=1 ;;
    --dry-run)    DRY_RUN=1 ;;
    -h|--help)    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) err "unknown arg: $1"; exit 1 ;;
  esac
  shift || true
done

# Host CPU as gn spells it. sysctl, not `uname -m`: a Rosetta-translated
# shell reports x86_64 on Apple Silicon.
if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null)" == "1" ]]; then CPU="arm64"; else CPU="x64"; fi

V8_DIR="$DEST/v8"
step "V8 sync"
info "workdir:  $DEST   (source: $V8_DIR)"
info "ref:      $REF"
info "cpu:      $CPU"
[[ "$SHALLOW" == "1" ]] && info "mode:     shallow first fetch (--no-history)"

have git     || { err "git not found (install Xcode CLT)"; exit 1; }
have python3 || { err "python3 not found (depot_tools needs it)"; exit 1; }

# ── depot_tools (fetch, gclient, gn, autoninja) ─────────────────────
# A FULL clone, not part of tools-sync's shallow manifest: depot_tools
# updates itself with git on every gclient run.
if have gclient && [[ ! -d "$DEPOT_TOOLS" ]]; then
  DEPOT_TOOLS="$(dirname "$(command -v gclient)")"
  info "using depot_tools already on PATH: $DEPOT_TOOLS"
elif [[ -d "$DEPOT_TOOLS/.git" ]]; then
  ok "depot_tools present: $DEPOT_TOOLS (self-updates on gclient runs)"
elif [[ -e "$DEPOT_TOOLS" ]]; then
  err "$DEPOT_TOOLS exists but is not a git clone — move it or set DEPOT_TOOLS=..."
  exit 1
else
  info "cloning depot_tools -> $DEPOT_TOOLS"
  run mkdir -p "$(dirname "$DEPOT_TOOLS")"
  run git clone "$DEPOT_URL" "$DEPOT_TOOLS" || { err "depot_tools clone failed"; exit 1; }
fi
# Appended, per Chromium's mac instructions, so brew's tools keep priority.
export PATH="$PATH:$DEPOT_TOOLS"

SYNC_ARGS=(sync --revision "v8@$REF")
[[ -n "$JOBS" ]] && SYNC_ARGS+=(-j "$JOBS")

# ── fetch (first time) or update ────────────────────────────────────
# `fetch v8` refuses to run where a .gclient already exists, so it is only
# used for the first checkout; later runs move v8/ to $REF via gclient.
# --revision makes this independent of the solution's `managed` setting.
if [[ ! -f "$DEST/.gclient" ]]; then
  if [[ -e "$V8_DIR" ]]; then
    err "$V8_DIR exists but $DEST/.gclient does not — not a gclient checkout."
    err "Move it aside or pick another workdir with -d."
    exit 1
  fi
  FETCH_ARGS=(fetch)
  [[ "$SHALLOW" == "1" ]] && FETCH_ARGS+=(--no-history)
  FETCH_ARGS+=(v8)
  info "${FETCH_ARGS[*]}   (several GB; first run takes a while)"
  run mkdir -p "$DEST"
  if [[ "$DRY_RUN" == "1" ]]; then
    info "(dry-run) would run the above in $DEST"
  else
    ( cd "$DEST" && "${FETCH_ARGS[@]}" ) || { err "fetch v8 failed (re-run to resume: it continues with gclient sync)"; exit 1; }
  fi
  # fetch lands on main; only re-sync if a different ref was asked for.
  if [[ "$REF" != "origin/main" ]]; then
    [[ "$SHALLOW" == "1" ]] && warn "--shallow + -r: the ref must be reachable without history"
    info "gclient ${SYNC_ARGS[*]}"
    if [[ "$DRY_RUN" != "1" ]]; then
      ( cd "$DEST" && gclient "${SYNC_ARGS[@]}" ) || { err "gclient sync to $REF failed"; exit 1; }
    fi
  fi
else
  ok "existing checkout: $DEST/.gclient"
  # Never move a tree with local edits (your patches/PoCs live there).
  if [[ -d "$V8_DIR/.git" && -n "$(git -C "$V8_DIR" status --porcelain --untracked-files=no 2>/dev/null)" ]]; then
    err "$V8_DIR has uncommitted changes — commit/stash them, then re-run."
    exit 1
  fi
  info "gclient ${SYNC_ARGS[*]}"
  if [[ "$DRY_RUN" != "1" ]]; then
    ( cd "$DEST" && gclient "${SYNC_ARGS[@]}" ) || { err "gclient sync failed (re-run to resume)"; exit 1; }
  fi
fi
[[ "$DRY_RUN" != "1" ]] && ok "V8 synced: $(git -C "$V8_DIR" log -1 --format='%h %cs %s' 2>/dev/null)"

# ── Builds (optional) ───────────────────────────────────────────────
need_xcode() {
  local dev; dev="$(xcode-select -p 2>/dev/null || true)"
  if [[ "$dev" != *.app/Contents/Developer ]]; then
    err "building V8 needs full Xcode; xcode-select points at: ${dev:-nothing}"
    err "install Xcode (mas install 497799835), then:"
    err "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    return 1
  fi
}

# gn_build <outdir> <gn args>
gn_build() {
  local out="$1" args="$2"
  info "gn gen $out --args='$args'"
  info "autoninja -C $out d8"
  [[ "$DRY_RUN" == "1" ]] && return 0
  ( cd "$V8_DIR" && gn gen "$out" --args="$args" && autoninja -C "$out" d8 ) \
    || { err "build failed: $out"; return 1; }
  ok "built $V8_DIR/$out/d8"
}

RC=0
if [[ "$BUILD" == "1" || "$FUZZBUILD" == "1" ]]; then
  need_xcode || exit 1
fi

if [[ "$BUILD" == "1" ]]; then
  step "Building release d8"
  gn_build "out/$CPU.release" "is_debug=false target_cpu=\"$CPU\"" || RC=1
fi

if [[ "$FUZZBUILD" == "1" ]]; then
  step "Building Fuzzilli-instrumented d8"
  # Same args as fuzzilli/Targets/V8/fuzzbuild.sh, which is now Linux-only
  # (it prints "Unsupported operating system" on macOS and hardcodes x64),
  # so the gn args are reproduced here with the host CPU.
  gn_build "out/fuzzbuild" \
    "is_debug=false dcheck_always_on=true v8_static_library=true v8_enable_verify_heap=true v8_enable_partition_alloc=false v8_fuzzilli=true sanitizer_coverage_flags=\"trace-pc-guard\" target_cpu=\"$CPU\"" \
    || RC=1
fi

# ── Fuzzilli (optional) ─────────────────────────────────────────────
if [[ "$FUZZILLI" == "1" ]]; then
  step "Fuzzilli"
  bash "$SCRIPT_DIR/tools-sync.sh" --only fuzzilli --dest "$(dirname "$FUZZILLI_DIR")" || RC=1
  if [[ "$DRY_RUN" == "1" ]]; then
    info "(dry-run) would run: swift build -c release   in $FUZZILLI_DIR"
  elif [[ -f "$FUZZILLI_DIR/Package.swift" ]]; then
    # Package.swift's first line pins the minimum Swift toolchain; check it
    # up front instead of failing deep inside SwiftPM.
    need="$(sed -nE '1s#^// *swift-tools-version: *([0-9]+\.[0-9]+).*#\1#p' "$FUZZILLI_DIR/Package.swift")"
    have_v="$(swift --version 2>/dev/null | sed -nE 's/.*Swift version ([0-9]+\.[0-9]+).*/\1/p' | head -1)"
    info "Swift: have ${have_v:-none}, Fuzzilli needs ${need:-?}"
    if [[ -n "$need" && -n "$have_v" ]] && \
       [[ "$(printf '%s\n%s\n' "$need" "$have_v" | sort -t. -k1,1n -k2,2n | head -1)" != "$need" ]]; then
      err "Swift $have_v is too old for Fuzzilli (needs $need). Update Xcode, or:"
      err "  brew install swiftly && swiftly init && swiftly install $need"
      RC=1
    else
      ( cd "$FUZZILLI_DIR" && swift build -c release ) && ok "Fuzzilli built" \
        || { err "swift build failed in $FUZZILLI_DIR"; RC=1; }
    fi
  else
    err "Fuzzilli clone missing at $FUZZILLI_DIR"; RC=1
  fi
fi

cat <<EOF

Next steps:
  • Shell setup: depot_tools must be on PATH (the zshrc appends ~/tools/depot_tools).
  • Update later:   scripts/v8-sync.sh            (or: cd $DEST && gclient sync)
  • Release d8:     scripts/v8-sync.sh --build    (or: cd $V8_DIR && tools/dev/gm.py $CPU.release)
  • Fuzz V8 with Fuzzilli (after --fuzzilli):
      cd $FUZZILLI_DIR
      swift run -c release FuzzilliCli --profile=v8 --storagePath=\$HOME/fuzz/v8 \\
        $V8_DIR/out/fuzzbuild/d8
    Keep crash dialogs off while fuzzing (macos-defaults.sh sets
    com.apple.CrashReporter DialogType=none).
EOF
exit "$RC"
