#!/usr/bin/env bash
# scripts/frida-server.sh — download the frida-server matching the
# installed frida client and push it to a connected Android device.
#
# Usage:
#   scripts/frida-server.sh [arch]
#     arch defaults to the device's ABI (adb). Common: arm64 arm x86_64
#
# The server version is taken from the installed `frida` client so the
# two always match (mismatched versions fail to attach).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

have frida || { err "frida client not installed (run scripts/python-tools.sh)"; exit 1; }
have adb   || { err "adb not found (install android-platform-tools)"; exit 1; }

# NOTE: the `|| true` on these assignments is load-bearing. Under
# `set -euo pipefail`, a failing pipeline in a command substitution (frida
# erroring, or adb exiting non-zero because no device is attached) would make
# the assignment fail and abort the script *silently* — before the explicit
# error checks below could run. `|| true` lets us test the result and print a
# useful message instead.
VERSION="$(frida --version 2>/dev/null | tr -d '[:space:]')" || true
[[ -n "$VERSION" ]] || { err "could not read 'frida --version' (is the frida client working?)"; exit 1; }
info "frida client version: $VERSION"

# Determine device ABI if arch not given.
ARCH="${1:-}"
if [[ -z "$ARCH" ]]; then
  abi="$(adb shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '[:space:]')" || true
  if [[ -z "$abi" ]]; then
    err "no Android device reachable via adb (check 'adb devices' — connected and authorized?)"
    err "or pass the arch explicitly, e.g.:  scripts/frida-server.sh arm64"
    exit 1
  fi
  case "$abi" in
    arm64*)  ARCH="arm64" ;;
    armeabi*) ARCH="arm" ;;
    x86_64)  ARCH="x86_64" ;;
    x86)     ARCH="x86" ;;
    *) err "unknown device ABI '$abi' — pass arch explicitly"; exit 1 ;;
  esac
  info "detected device ABI: $abi -> $ARCH"
fi

NAME="frida-server-${VERSION}-android-${ARCH}"
URL="https://github.com/frida/frida/releases/download/${VERSION}/${NAME}.xz"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

info "downloading $URL"
run curl -fL "$URL" -o "$TMP/$NAME.xz"
run unxz "$TMP/$NAME.xz"
run chmod +x "$TMP/$NAME"

info "pushing to device (/data/local/tmp/frida-server)"
run adb push "$TMP/$NAME" /data/local/tmp/frida-server
run adb shell "chmod 755 /data/local/tmp/frida-server"

ok "frida-server $VERSION ($ARCH) deployed."
cat <<'EOF'
Start it (device must be rooted):
  adb root            # or: adb shell su -c ...
  adb shell "/data/local/tmp/frida-server &"
Then on the host:
  frida-ps -U
EOF
