#!/usr/bin/env bash
# scripts/python-tools.sh — install mobile-dev Python CLIs via uv.
# Frida client and frida-server MUST match versions; we pin one version
# here and the frida-server helper downloads the SAME one for the device.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

step "Python mobile-dev tooling (via uv)"

# uv installs tool shims into ~/.local/bin; make sure it's on PATH for
# THIS process (install.sh doesn't source the new zshrc).
export PATH="$HOME/.local/bin:$PATH"

if ! have uv; then
  err "uv not found. Install first:  brew install uv"
  exit 1
fi

# Optional version pin. If a FRIDA_VERSION file exists, pin the client to it;
# otherwise install latest and record what we got, so re-runs are stable.
# (frida-server.sh does NOT read this file — it reads the installed client's
# `frida --version` directly, which is what actually has to match the server.)
FRIDA_VERSION="$(cat "$SCRIPT_DIR/../FRIDA_VERSION" 2>/dev/null || echo "")"
if [[ -z "$FRIDA_VERSION" ]]; then
  # Default: let uv resolve the latest, then record it for the server helper.
  info "no pinned FRIDA_VERSION; installing latest frida-tools and recording it"
fi

# uv tool install = isolated venv per CLI, on PATH via ~/.local/bin.
install_tool() {   # $1 = package spec, $2+ = extra args
  local spec="$1"; shift || true
  info "uv tool install $spec $*"
  run uv tool install --force "$@" "$spec"
}

# Frida: pin tools to the chosen version if set, else latest.
if [[ -n "$FRIDA_VERSION" ]]; then
  install_tool "frida-tools" --with "frida==$FRIDA_VERSION"
else
  install_tool "frida-tools"
fi

# objection depends on frida; install into its own env with matching frida.
if [[ -n "$FRIDA_VERSION" ]]; then
  install_tool "objection" --with "frida==$FRIDA_VERSION"
else
  install_tool "objection"
fi

# Other staples. Each isolated; failures don't abort the rest.
# (mitmproxy comes from Homebrew; frida-tools is installed above — do not
# re-add them here or the unpinned version would clobber the pinned one.)
for pkg in \
  apkleaks \
  androguard ; do
  install_tool "$pkg" || warn "failed: $pkg (continuing)"
done

# Record the resolved frida version so the server helper matches it.
if [[ -z "$FRIDA_VERSION" && "${DRY_RUN:-0}" != "1" ]]; then
  resolved="$(frida --version 2>/dev/null || true)"
  if [[ -n "$resolved" ]]; then
    printf '%s\n' "$resolved" > "$SCRIPT_DIR/../FRIDA_VERSION"
    ok "recorded frida version $resolved -> FRIDA_VERSION"
  fi
fi

ok "Python tooling installed. Try:  frida --version ; objection version"
