#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║   install.sh — fresh macOS setup for a mobile developer            ║
# ╚══════════════════════════════════════════════════════════════════╝
# Idempotent, re-runnable. Intended for a FRESH Apple Silicon Mac, but
# degrades on Intel. Safe to run multiple times.
#
#   ./install.sh                  # run all core steps
#   ./install.sh --dry-run        # print what would happen, change nothing
#   ./install.sh --only dotfiles  # run only one (or more) steps
#   ./install.sh --skip android   # run all except the listed steps
#   ./install.sh --tools          # git-clone the ~/tools toolkit (clone-only)
#   ./install.sh --v8             # also fetch V8 via depot_tools (multi-GB, no build)
#   ./install.sh --help
#
# Steps (in order): clt rosetta homebrew brew dotfiles gitconfig python android macos
#
# NOTE: errexit (set -e) is deliberately NOT used — one failing step must
# not abort the rest. Failures are collected and reported at the end, and
# the script exits non-zero if any step failed.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$REPO_DIR/scripts/lib.sh"

ALL_STEPS=(clt rosetta homebrew brew dotfiles gitconfig python android macos)
ONLY=(); SKIP=(); DO_TOOLS=0; DO_V8=0
FAILED=()
export DRY_RUN=0

# ── Logging: tee everything to a timestamped log ────────────────────
LOG_DIR="$REPO_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)  DRY_RUN=1 ;;
    --tools)    DO_TOOLS=1 ;;
    --v8)       DO_V8=1 ;;
    --only)     shift; IFS=', ' read -r -a ONLY <<<"${1:-}" ;;
    --skip)     shift; IFS=', ' read -r -a SKIP <<<"${1:-}" ;;
    -h|--help)  usage 0 ;;
    *) err "unknown arg: $1"; usage 1 ;;
  esac
  shift || true
done

should_run() {
  local s="$1" x
  if [[ "${#SKIP[@]}" -gt 0 ]]; then
    for x in "${SKIP[@]}"; do [[ "$x" == "$s" ]] && return 1; done
  fi
  if [[ "${#ONLY[@]}" -gt 0 ]]; then
    for x in "${ONLY[@]}"; do [[ "$x" == "$s" ]] && return 0; done
    return 1
  fi
  return 0
}

# ── sudo keepalive (skipped in dry-run) ─────────────────────────────
keep_sudo_alive() {
  [[ "$DRY_RUN" == "1" ]] && return 0
  info "requesting sudo (kept alive for the duration)…"
  sudo -v
  # Detach the keepalive's fds from our stdout/stderr. Otherwise, when the
  # EXIT trap kills this subshell, its in-flight `sleep` is orphaned and keeps
  # the `| tee` pipe's write end open — hanging the script up to 60s at exit.
  ( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) \
    </dev/null >/dev/null 2>&1 &
  SUDO_PID=$!
  trap '[[ -n "${SUDO_PID:-}" ]] && kill "$SUDO_PID" 2>/dev/null || true' EXIT
}

# Make brew, ~/.local/bin and JAVA_HOME available to THIS script and the
# component scripts it spawns (the new zshrc is not sourced here). Safe to
# call repeatedly; guards every lookup so it never trips `set -u`.
refresh_env() {
  if [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then eval "$(/usr/local/bin/brew shellenv)"; fi
  case ":${PATH}:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
  if /usr/libexec/java_home >/dev/null 2>&1; then
    export JAVA_HOME="$(/usr/libexec/java_home)"
  fi
}

# ════════════════════════════════════════════════════════════════════
# Step implementations
# ════════════════════════════════════════════════════════════════════

step_clt() {
  step "Xcode Command Line Tools"
  if xcode-select -p >/dev/null 2>&1; then
    ok "already installed ($(xcode-select -p))"; return
  fi
  if [[ "$DRY_RUN" == "1" ]]; then info "would run: xcode-select --install"; return; fi
  xcode-select --install || true
  info "waiting for Command Line Tools to finish installing (ctrl-C to abort)…"
  local waited=0
  until xcode-select -p >/dev/null 2>&1; do
    sleep 10; waited=$((waited + 10))
    if (( waited >= 1800 )); then
      err "timed out after 30m — was the install dialog cancelled? Re-run this step."
      return 1
    fi
  done
  ok "Command Line Tools installed"
}

step_rosetta() {
  step "Rosetta 2 (Apple Silicon only)"
  if [[ "$(uname -m)" != "arm64" ]]; then ok "not Apple Silicon; skipping"; return; fi
  # `pgrep oahd` only says whether the daemon happens to be running, not
  # whether Rosetta is installed. Check for its runtime, then fall back to
  # running x86_64 code (system binaries may drop their x86_64 slice later).
  if [[ -e /Library/Apple/usr/libexec/oah/libRosettaRuntime ]] \
     || arch -x86_64 /usr/bin/true 2>/dev/null; then
    ok "Rosetta already present"; return
  fi
  run softwareupdate --install-rosetta --agree-to-license
}

step_homebrew() {
  step "Homebrew"
  if have brew; then
    ok "already installed"
  elif [[ "$DRY_RUN" == "1" ]]; then
    info "would install Homebrew (NONINTERACTIVE)"
  else
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  # Load brew into THIS script's environment.
  if [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then eval "$(/usr/local/bin/brew shellenv)"; fi
  # Don't let this function fall through returning the status of an untaken
  # `if` (which is 0) — a failed install would otherwise be reported as OK.
  [[ "$DRY_RUN" == "1" ]] && return 0
  have brew || { err "Homebrew install did not complete (brew not on PATH)"; return 1; }
  return 0
}

step_brew() {
  step "Homebrew bundle (core)"
  have brew || { err "brew missing; run the homebrew step first"; return 1; }
  run brew update
  # brew bundle exits non-zero if ANY item fails; we want to continue and
  # report, so don't let it abort the whole script.
  if [[ "$DRY_RUN" == "1" ]]; then
    info "would run: brew bundle --file=$REPO_DIR/Brewfile"
  else
    brew bundle --file="$REPO_DIR/Brewfile" || warn "some brew items failed (see log above)"
  fi

  # Symlink brew's JDK so /usr/libexec/java_home can find it.
  local jdk
  for jdk in openjdk@17 openjdk openjdk@21 openjdk@11; do
    local src="$HOMEBREW_PREFIX/opt/$jdk/libexec/openjdk.jdk"
    if [[ -d "$src" ]]; then
      local dest="/Library/Java/JavaVirtualMachines/$jdk.jdk"
      if [[ ! -e "$dest" ]]; then
        info "symlinking $jdk into system JVM dir (sudo)"
        run sudo ln -sfn "$src" "$dest"
      fi
    fi
  done

  # Recreate the python/python3 -> python@3.14 shims in ~/.local/bin
  # (the zshrc keeps ~/.local/bin first so these win over system python3).
  local py="$HOMEBREW_PREFIX/bin/python3.14"
  if [[ -x "$py" ]]; then
    run mkdir -p "$HOME/.local/bin"
    run ln -sfn "$py" "$HOME/.local/bin/python3"
    run ln -sfn "$py" "$HOME/.local/bin/python"
    ok "python/python3 -> python3.14 shims created in ~/.local/bin"
  fi
  # Bundle/JDK/shim steps are intentionally best-effort (failures are warned,
  # not fatal). Return success explicitly so a future edit can't accidentally
  # leak a non-zero status — or mask a real one behind an untaken `if`.
  return 0
}

step_dotfiles() {
  step "Dotfiles"
  local rc=0
  # The .zshrc symlink is the one real failure that must be reported (e.g.
  # source missing). The plugin clones below are best-effort (|| true).
  link_file "$REPO_DIR/dotfiles/zshrc" "$HOME/.zshrc" || rc=1
  # Seed ~/.zshrc.local from the example if it doesn't exist yet.
  if [[ ! -f "$HOME/.zshrc.local" ]]; then
    run cp "$REPO_DIR/dotfiles/zshrc.local.example" "$HOME/.zshrc.local"
    ok "created ~/.zshrc.local (edit for machine-specific PATHs/secrets)"
  else
    ok "~/.zshrc.local already exists; left untouched"
  fi
  # Clone zsh plugins as a fallback (zshrc prefers brew copies).
  local zdir="$HOME/.zsh"
  run mkdir -p "$zdir"
  if [[ ! -d "$zdir/zsh-autosuggestions" ]]; then
    run git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$zdir/zsh-autosuggestions" || true
  fi
  if [[ ! -d "$zdir/zsh-syntax-highlighting" ]]; then
    run git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting "$zdir/zsh-syntax-highlighting" || true
  fi
  return "$rc"
}

step_gitconfig() {
  step "Git identity"
  if [[ -f "$HOME/.gitconfig" ]] && git config --global user.email >/dev/null 2>&1; then
    ok "git identity already set ($(git config --global user.email)); leaving as-is"
    return
  fi
  local name="${GIT_NAME:-}" email="${GIT_EMAIL:-}"
  if [[ "$DRY_RUN" == "1" ]]; then
    info "would configure git identity (prompt or GIT_NAME/GIT_EMAIL)"; return
  fi
  [[ -z "$name"  ]] && read -r -p "Git user.name: "  name
  [[ -z "$email" ]] && read -r -p "Git user.email: " email
  # Start from the template, then set identity.
  [[ -f "$HOME/.gitconfig" ]] || cp "$REPO_DIR/dotfiles/gitconfig.example" "$HOME/.gitconfig" || return 1
  git config --global user.name  "$name"           || return 1
  git config --global user.email "$email"          || return 1
  git config --global init.defaultBranch main      || return 1
  ok "git identity set: $name <$email>"
}

step_python() { bash "$REPO_DIR/scripts/python-tools.sh"; }
step_android() { bash "$REPO_DIR/scripts/android.sh"; }
step_macos()   { bash "$REPO_DIR/scripts/macos-defaults.sh"; }
step_tools()   { bash "$REPO_DIR/scripts/tools-sync.sh"; }
step_v8()      { bash "$REPO_DIR/scripts/v8-sync.sh"; }

# ════════════════════════════════════════════════════════════════════
main() {
  info "logging to $LOG_FILE"
  [[ "$DRY_RUN" == "1" ]] && warn "DRY RUN — no changes will be made"
  keep_sudo_alive
  refresh_env     # so `--only brew` etc. work from a shell without brew in env

  local s
  for s in "${ALL_STEPS[@]}"; do
    if should_run "$s"; then
      if "step_$s"; then
        [[ "$s" == "homebrew" || "$s" == "brew" ]] && refresh_env
      else
        err "step failed: $s"
        FAILED+=("$s")
      fi
    else
      info "skipping step: $s"
    fi
  done

  # Optional: git-clone the ~/tools toolkit (only when --tools is passed).
  if [[ "$DO_TOOLS" == "1" ]]; then
    if step_tools; then :; else err "step failed: tools"; FAILED+=("tools"); fi
  fi
  # Optional: fetch V8 source (only when --v8 is passed). Building d8 / the
  # Fuzzilli target needs full Xcode, so that stays a manual follow-up.
  if [[ "$DO_V8" == "1" ]]; then
    if step_v8; then :; else err "step failed: v8"; FAILED+=("v8"); fi
  fi

  step "Done"
  if [[ "${#FAILED[@]}" -gt 0 ]]; then
    warn "completed with failures in: ${FAILED[*]}"
    # tools/v8 are opt-in flags, not --only steps: point at their scripts.
    local core=() f
    for f in "${FAILED[@]}"; do
      case "$f" in
        tools) warn "re-run tools with:  scripts/tools-sync.sh" ;;
        v8)    warn "re-run v8 with:     scripts/v8-sync.sh" ;;
        *)     core+=("$f") ;;
      esac
    done
    [[ "${#core[@]}" -gt 0 ]] && warn "re-run just those with:  ./install.sh --only $(IFS=,; echo "${core[*]}")"
  else
    ok "All steps completed. Open a new terminal (or run: exec zsh)."
  fi
  cat <<EOF

Next / manual steps (cannot be fully automated):
  • Sign in to the Mac App Store, then: mas install <id>   (e.g. Xcode)
  • Burp Suite Professional, IDA Pro, JEB — licensed installers
  • Full Xcode — via App Store / developer.apple.com
  • Push frida-server to a device:  scripts/frida-server.sh
  • V8 + Fuzzilli (after full Xcode):  scripts/v8-sync.sh --build --fuzzilli
  • Review macOS defaults applied in scripts/macos-defaults.sh
  • Manual-only apps: Sideloadly, PixelFlasher, Bytecode-Viewer (see README)
EOF
  [[ "${#FAILED[@]}" -gt 0 ]] && return 1 || return 0
}

# Run main, teeing all output to the log. pipefail propagates main's
# non-zero exit through the tee pipeline. PIPESTATUS[0] = main's status.
main 2>&1 | tee "$LOG_FILE"
rc="${PIPESTATUS[0]:-0}"

# lib.sh enables color when stdout is a tty — which it is here (the terminal),
# so install.sh's own messages carry ANSI escapes and tee copies them into the
# log. Strip them from the on-disk copy so the log stays plain text; the
# terminal keeps its color. Done synchronously (not via a >(...) that could be
# killed on exit). BSD/macOS sed needs a literal ESC, not \x1b.
if [[ -s "$LOG_FILE" ]]; then
  _esc=$(printf '\033')
  _tmp="$(mktemp)" && LC_ALL=C sed -E "s/${_esc}\[[0-9;]*m//g" "$LOG_FILE" >"$_tmp" \
    && mv "$_tmp" "$LOG_FILE"
fi
exit "$rc"
