#!/usr/bin/env bash
# scripts/lib.sh — shared helpers for the macOS setup scripts.
# Sourced by install.sh and the component scripts; not run directly.

# ── Colors (disabled if not a tty) ──────────────────────────────────
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
  C_BLU=$'\033[34m'; C_CYA=$'\033[36m'; C_GRY=$'\033[90m'
else
  C_RESET=; C_BOLD=; C_RED=; C_GRN=; C_YEL=; C_BLU=; C_CYA=; C_GRY=
fi

info()  { printf '%s[*]%s %s\n' "$C_BLU" "$C_RESET" "$*"; }
ok()    { printf '%s[+]%s %s\n' "$C_GRN" "$C_RESET" "$*"; }
warn()  { printf '%s[!]%s %s\n' "$C_YEL" "$C_RESET" "$*" >&2; }
err()   { printf '%s[x]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
step()  { printf '\n%s==>%s %s%s%s\n' "$C_CYA" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"; }

# DRY_RUN is exported by install.sh. run() echoes-only when set.
run() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%s[dry-run]%s %s\n' "$C_GRY" "$C_RESET" "$*"
  else
    "$@"
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# Append a line to a file only if it's not already present.
ensure_line() {
  local line="$1" file="$2"
  [[ -f "$file" ]] || { run touch "$file"; }
  if ! grep -qxF "$line" "$file" 2>/dev/null; then
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
      printf '%s[dry-run]%s append to %s: %s\n' "$C_GRY" "$C_RESET" "$file" "$line"
    else
      printf '%s\n' "$line" >> "$file"
    fi
  fi
}

# Back up an existing file/symlink to <path>.bak.<timestamp>, then
# symlink src -> dest. Never clobbers silently.
link_file() {
  local src="$1" dest="$2"
  if [[ ! -e "$src" ]]; then
    err "source missing: $src"; return 1
  fi
  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    ok "already linked: $dest"; return 0
  fi
  if [[ -e "$dest" || -L "$dest" ]]; then
    local bak="${dest}.bak.$(date +%Y%m%d-%H%M%S)"
    warn "backing up existing $dest -> $bak"
    run mv "$dest" "$bak"
  fi
  run ln -s "$src" "$dest"
  ok "linked $dest -> $src"
}
