#!/usr/bin/env bash
# scripts/tools-sync.sh — clone (or update) a curated set of mobile / RE /
# recon tools into ~/tools. SOURCE-ONLY: it git-clones and `git pull`s; it
# does NOT build or install anything. Each tool has its own build/venv step
# (see the hints printed at the end, and each project's README).
#
# Usage:
#   scripts/tools-sync.sh                 # clone/update everything into ~/tools
#   scripts/tools-sync.sh --dry-run       # print actions, change nothing
#   scripts/tools-sync.sh --dest ~/tools  # custom destination (default: ~/tools)
#   scripts/tools-sync.sh --only ffuf,angr
#   scripts/tools-sync.sh --skip SecLists,nuclei-templates
#   scripts/tools-sync.sh --full          # full history (default: shallow --depth=1)
#   scripts/tools-sync.sh --list          # print the manifest and exit
#   scripts/tools-sync.sh --help
#
# Idempotent: a tool already cloned is updated with `git pull --ff-only`; a
# NON-git directory of the same name is left untouched (warned, never
# clobbered) — so it coexists with whatever is already in ~/tools.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

DEST="$HOME/tools"
SHALLOW=1
LIST_ONLY=0
ONLY=(); SKIP=()
export DRY_RUN="${DRY_RUN:-0}"

# Manifest — "dir|git-url|build-kind". dir = folder created under $DEST.
# build-kind is informational only (clone-only mode never builds); it drives
# the build hints printed at the end. Grouped by category.
TOOLS=(
  # ── Android / iOS ──────────────────────────────────────────────────
  "objection|https://github.com/sensepost/objection|py"
  "APKiD|https://github.com/rednaga/APKiD|py"
  "jadx|https://github.com/skylot/jadx|gradle"
  "pymobiledevice3|https://github.com/doronz88/pymobiledevice3|py"
  "mtkclient|https://github.com/bkerler/mtkclient|py"
  "edl|https://github.com/bkerler/edl|py"
  "frida-ios-dump|https://github.com/AloneMonkey/frida-ios-dump|py"
  "medusa|https://github.com/Ch0pin/medusa|py"
  "MobSF|https://github.com/MobSF/Mobile-Security-Framework-MobSF|py"
  "react-native-decompiler|https://github.com/numandev1/react-native-decompiler|node"
  "disable-flutter-tls-verification|https://github.com/NVISOsecurity/disable-flutter-tls-verification|frida"
  "AlwaysTrustUserCerts|https://github.com/NVISOsecurity/AlwaysTrustUserCerts|frida"
  "brokkr-flash|https://github.com/Gabriel2392/brokkr-flash|cmake"
  # ── Reverse engineering ────────────────────────────────────────────
  "angr|https://github.com/angr/angr|py"
  "r2frida|https://github.com/nowsecure/r2frida|make"
  "crabviz|https://github.com/chanhx/crabviz|rust"
  # ── JS engine fuzzing (V8 itself: scripts/v8-sync.sh) ──────────────
  "fuzzilli|https://github.com/googleprojectzero/fuzzilli|swift"
  # ── Recon / web ─────────────────────────────────────────────────────
  "sqlmap|https://github.com/sqlmapproject/sqlmap|py"
  "SecLists|https://github.com/danielmiessler/SecLists|data"
  "GitTools|https://github.com/internetwache/GitTools|sh"
  "ffuf|https://github.com/ffuf/ffuf|go"
  "gobuster|https://github.com/OJ/gobuster|go"
  "feroxbuster|https://github.com/epi052/feroxbuster|rust"
  "subfinder|https://github.com/projectdiscovery/subfinder|go"
  "amass|https://github.com/owasp-amass/amass|go"
  "httpx|https://github.com/projectdiscovery/httpx|go"
  "nuclei|https://github.com/projectdiscovery/nuclei|go"
  "nuclei-templates|https://github.com/projectdiscovery/nuclei-templates|data"
  "katana|https://github.com/projectdiscovery/katana|go"
  "naabu|https://github.com/projectdiscovery/naabu|go"
  "dnsx|https://github.com/projectdiscovery/dnsx|go"
  "gau|https://github.com/lc/gau|go"
  "trufflehog|https://github.com/trufflesecurity/trufflehog|go"
  "gitleaks|https://github.com/gitleaks/gitleaks|go"
  "reconftw|https://github.com/six2dez/reconftw|sh"
)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)  DRY_RUN=1 ;;
    --full)     SHALLOW=0 ;;
    --dest)     shift; DEST="${1:-}" ;;
    --only)     shift; IFS=', ' read -r -a ONLY <<<"${1:-}" ;;
    --skip)     shift; IFS=', ' read -r -a SKIP <<<"${1:-}" ;;
    --list)     LIST_ONLY=1 ;;
    -h|--help)  sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) err "unknown arg: $1"; exit 1 ;;
  esac
  shift || true
done

# Should this tool be processed? (same precedence as install.sh: skip wins)
want() {
  local name="$1" x
  if [[ "${#SKIP[@]}" -gt 0 ]]; then
    for x in "${SKIP[@]}"; do [[ "$x" == "$name" ]] && return 1; done
  fi
  if [[ "${#ONLY[@]}" -gt 0 ]]; then
    for x in "${ONLY[@]}"; do [[ "$x" == "$name" ]] && return 0; done
    return 1
  fi
  return 0
}

if [[ "$LIST_ONLY" == "1" ]]; then
  step "tools-sync manifest (${#TOOLS[@]} tools)"
  for entry in "${TOOLS[@]}"; do
    IFS='|' read -r dir url kind <<<"$entry"
    printf '  %-32s %-9s %s\n' "$dir" "[$kind]" "$url"
  done
  exit 0
fi

have git || { err "git not found (install Xcode CLT)"; exit 1; }

step "Syncing tools into $DEST"
[[ "$SHALLOW" == "1" ]] && info "mode: shallow (--depth=1; use --full for history)"
run mkdir -p "$DEST"

CLONED=0; UPDATED=0; FAILED=(); LEFT=()
for entry in "${TOOLS[@]}"; do
  IFS='|' read -r dir url kind <<<"$entry"
  want "$dir" || { info "skip (filtered): $dir"; continue; }
  target="$DEST/$dir"

  if [[ -d "$target/.git" ]]; then
    info "update: $dir"
    if run git -C "$target" pull --ff-only; then
      UPDATED=$((UPDATED + 1))
    else
      warn "pull failed (diverged or shallow conflict): $dir"; FAILED+=("$dir")
    fi
  elif [[ -e "$target" ]]; then
    warn "exists but is not a git clone — leaving untouched: $target"
    LEFT+=("$dir")
  else
    info "clone:  $dir"
    clone_args=(clone)
    [[ "$SHALLOW" == "1" ]] && clone_args+=(--depth=1)
    clone_args+=("$url" "$target")
    if run git "${clone_args[@]}"; then
      CLONED=$((CLONED + 1))
    else
      warn "clone failed: $dir ($url)"; FAILED+=("$dir")
    fi
  fi
done

step "tools-sync summary"
ok "cloned: $CLONED   updated: $UPDATED"
[[ "${#LEFT[@]}"   -gt 0 ]] && warn "left untouched (non-git dirs already present): ${LEFT[*]}"
[[ "${#FAILED[@]}" -gt 0 ]] && err  "failed: ${FAILED[*]}  (re-run with: --only $(IFS=,; echo "${FAILED[*]}"))"

cat <<'EOF'

These are SOURCE clones — nothing was built. To make a tool runnable:
  • Python (angr, objection, mtkclient, edl, MobSF, sqlmap, …):
      cd ~/tools/<tool> && uv venv && uv pip install -r requirements.txt   # or: pipx install .
  • Go (ffuf, nuclei, httpx, subfinder, amass, katana, naabu, dnsx, gau, …):
      cd ~/tools/<tool> && go build ./...        # binary lands in the clone dir
  • Rust (feroxbuster, crabviz):   cd ~/tools/<tool> && cargo build --release
  • jadx:    cd ~/tools/jadx && ./gradlew dist   # -> build/jadx/bin
  • Swift (fuzzilli): cd ~/tools/fuzzilli && swift build -c release
      (or scripts/v8-sync.sh --fuzzilli: builds it + a fuzzing d8)
  • r2frida: needs radare2 first (brew install radare2), then `make`
  • Data (SecLists, nuclei-templates): nothing to build — point tools at them.
EOF

[[ "${#FAILED[@]}" -gt 0 ]] && exit 1 || exit 0
