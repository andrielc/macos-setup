#!/usr/bin/env bash
# scripts/android.sh — install Android SDK components via sdkmanager.
# Assumes `android-commandlinetools` cask (or Android Studio) is present.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"

# Locate sdkmanager: brew cask installs it under HOMEBREW_PREFIX.
find_sdkmanager() {
  local c
  for c in \
    "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" \
    "${HOMEBREW_PREFIX:-/opt/homebrew}/share/android-commandlinetools/cmdline-tools/latest/bin/sdkmanager" \
    "$(command -v sdkmanager 2>/dev/null || true)"; do
    [[ -n "$c" && -x "$c" ]] && { echo "$c"; return 0; }
  done
  return 1
}

step "Android SDK setup"

SDKMANAGER="$(find_sdkmanager || true)"
if [[ -z "$SDKMANAGER" ]]; then
  err "sdkmanager not found. Install first:  brew install --cask android-commandlinetools"
  exit 1
fi
info "using sdkmanager: $SDKMANAGER"

run mkdir -p "$ANDROID_SDK_ROOT"

# ── Resolve the newest STABLE packages from the channel ─────────────
# sdkmanager's stable channel (0) still lists rc/beta/canary builds, e.g.
# "ndk;30.0.15729638 | 30.0.15729638 rc2" or "platforms;android-37.2-beta3",
# so filter on both the package name and the version column. Override any
# pick with env vars (NDK_PKG, PLATFORM_PKG, BUILD_TOOLS_PKG, SYSIMG_PKG).
# The fallbacks are the newest stable builds as of 2026-10-14, used only if
# the listing can't be fetched (offline).
if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null)" == "1" ]]; then ABI="arm64-v8a"; else ABI="x86_64"; fi

info "resolving latest stable SDK packages (sdkmanager --list)"
SDK_LIST="$("$SDKMANAGER" --sdk_root="$ANDROID_SDK_ROOT" --list --channel=0 2>/dev/null)" || SDK_LIST=""

# latest_stable <ERE matching the full package name>
latest_stable() {
  awk -F'|' -v re="$1" '
    /^Available Packages:/ { on = 1; next }
    /^Available Updates:/  { on = 0 }
    on && NF >= 3 {
      name = $1; ver = $2
      gsub(/^[ \t]+|[ \t]+$/, "", name)
      if (name ~ re && ver !~ /(rc|beta|alpha)/) print name
    }' <<<"$SDK_LIST" | sort -u -V | tail -1
}

NDK_PKG="${NDK_PKG:-$(latest_stable '^ndk;[0-9.]+$')}"
PLATFORM_PKG="${PLATFORM_PKG:-$(latest_stable '^platforms;android-[0-9]+([.][0-9]+)?$')}"
BUILD_TOOLS_PKG="${BUILD_TOOLS_PKG:-$(latest_stable '^build-tools;[0-9.]+$')}"
CMAKE_PKG="${CMAKE_PKG:-$(latest_stable '^cmake;[0-9.]+$')}"
# Newest API that actually ships a google_apis image for this host's ABI
# (google_apis, not playstore, so `adb root` works). Often lags the platform.
SYSIMG_PKG="${SYSIMG_PKG:-$(latest_stable "^system-images;android-[0-9]+([.][0-9]+)?;google_apis;$ABI\$")}"

[[ -n "$SDK_LIST" ]] || warn "could not list SDK packages (offline?) — using fallback pins"
: "${NDK_PKG:=ndk;30.0.16248370}"
: "${PLATFORM_PKG:=platforms;android-37.2}"
: "${BUILD_TOOLS_PKG:=build-tools;37.0.0}"
: "${CMAKE_PKG:=cmake;4.1.2}"
: "${SYSIMG_PKG:=system-images;android-37.0;google_apis;$ABI}"

info "NDK:         $NDK_PKG"
info "platform:    $PLATFORM_PKG"
info "build-tools: $BUILD_TOOLS_PKG"
info "cmake:       $CMAKE_PKG (+ 3.22.1, the Android Gradle Plugin default)"
info "emulator:    $SYSIMG_PKG"

PACKAGES=(
  "platform-tools"
  "cmdline-tools;latest"
  "emulator"
  "$PLATFORM_PKG"
  "$BUILD_TOOLS_PKG"
  "$NDK_PKG"
  "$CMAKE_PKG"
  "cmake;3.22.1"
  "$SYSIMG_PKG"
)

# Accept licenses first (yes | ...). sdkmanager exits non-zero on EOF.
info "accepting SDK licenses"
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  printf '%s[dry-run]%s yes | %s --sdk_root=%s --licenses\n' \
    "$C_GRY" "$C_RESET" "$SDKMANAGER" "$ANDROID_SDK_ROOT"
else
  yes | "$SDKMANAGER" --sdk_root="$ANDROID_SDK_ROOT" --licenses >/dev/null || true
fi

info "installing SDK packages (this can take a while)"
# Try one bulk call (fastest). If it fails — e.g. a pinned version is no
# longer offered — retry package-by-package so one bad item can't block the
# rest. `set -e` is sidestepped by the `if !` / `||` guards.
if ! run "$SDKMANAGER" --sdk_root="$ANDROID_SDK_ROOT" "${PACKAGES[@]}"; then
  warn "bulk install failed; retrying package-by-package"
  sdk_failed=()
  for p in "${PACKAGES[@]}"; do
    run "$SDKMANAGER" --sdk_root="$ANDROID_SDK_ROOT" "$p" || sdk_failed+=("$p")
  done
  [[ ${#sdk_failed[@]} -gt 0 ]] && warn "could not install: ${sdk_failed[*]}"
fi

ok "Android SDK components installed under $ANDROID_SDK_ROOT"
API="${SYSIMG_PKG#system-images;android-}"; API="${API%%;*}"
info "Create an AVD with, e.g.:"
cat <<EOF
  avdmanager create avd -n pixel_api${API//./_} \\
    -k "$SYSIMG_PKG" -d pixel_9
EOF
