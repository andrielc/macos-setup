#!/usr/bin/env bash
# scripts/macos-defaults.sh — sensible macOS defaults for a dev box.
# Conservative: shows hidden files, speeds up the UI, tidies Finder.
# Re-runnable. Review before applying; comment out anything you dislike.
# Targets macOS 15 (Sequoia), 26 (Tahoe) and 27; version-specific keys are
# gated with os_ge below.
#
# NOTE: errexit (set -e) is deliberately NOT used — each write is best-effort
# (via dw / sdw below). Newer macOS locks down more prefs domains, and one
# refused write must not silently skip every setting after it.
#
# A successful `defaults write` only means the value was stored — macOS
# silently ignores keys it no longer reads. Spot-check in System Settings.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

step "Applying macOS defaults"

# dw  = best-effort `defaults` call: warn and count on failure, keep going.
# sdw = the same via sudo, for system-wide domains under /Library.
DW_FAILED=0
dw()  { run defaults "$@"      || { warn "failed: defaults $*";      DW_FAILED=$((DW_FAILED + 1)); }; }
sdw() { run sudo defaults "$@" || { warn "failed: sudo defaults $*"; DW_FAILED=$((DW_FAILED + 1)); }; }

# macOS major version: 15 = Sequoia, 26 = Tahoe, 27 = next. Apple jumped
# from 15 to 26; with SYSTEM_VERSION_COMPAT set, Tahoe+ can report 16, so
# treat 16 as 26 (there is no real macOS 16).
OS_MAJOR="$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)"
[[ "$OS_MAJOR" =~ ^[0-9]+$ ]] || OS_MAJOR=0
[[ "$OS_MAJOR" == "16" ]] && OS_MAJOR=26
info "detected macOS major version: $OS_MAJOR"
if [[ "$OS_MAJOR" -lt 15 ]]; then
  warn "written for macOS 15/26/27 — older releases may ignore some keys"
fi
os_ge() { [[ "$OS_MAJOR" -ge "$1" ]]; }

# ── Finder ──────────────────────────────────────────────────────────
dw write com.apple.finder AppleShowAllFiles -bool true          # show hidden files
dw write NSGlobalDomain AppleShowAllExtensions -bool true        # show all extensions
dw write com.apple.finder ShowPathbar -bool true
dw write com.apple.finder ShowStatusBar -bool true
dw write com.apple.finder FXDefaultSearchScope -string "SCcf"    # search current folder
dw write com.apple.finder FXEnableExtensionChangeWarning -bool false
dw write com.apple.finder _FXSortFoldersFirst -bool true
dw write com.apple.finder FXPreferredViewStyle -string "Nlsv"    # list view
dw write com.apple.finder _FXShowPosixPathInTitle -bool true     # full path in title bar
# Avoid .DS_Store on network/USB volumes (handy for device/image work)
dw write com.apple.desktopservices DSDontWriteNetworkStores -bool true
dw write com.apple.desktopservices DSDontWriteUSBStores -bool true
# Unhide ~/Library (Apple hides it by default).
[[ -d "$HOME/Library" ]] && run chflags nohidden "$HOME/Library"

# ── Screenshots ─────────────────────────────────────────────────────
run mkdir -p "$HOME/Screenshots"
dw write com.apple.screencapture location -string "$HOME/Screenshots"
dw write com.apple.screencapture type -string "png"
dw write com.apple.screencapture disable-shadow -bool true
# Write the file immediately instead of after the ~5 s floating thumbnail.
dw write com.apple.screencapture show-thumbnail -bool false

# ── Keyboard & text: fast repeat, no "smart" rewriting of code ──────
dw write NSGlobalDomain KeyRepeat -int 2                         # fastest the UI allows
dw write NSGlobalDomain InitialKeyRepeat -int 15
dw write NSGlobalDomain ApplePressAndHoldEnabled -bool false     # key repeat over accents
dw write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
dw write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
dw write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
dw write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
dw write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false  # "  " -> ". "
# Inline predictive text (Sonoma+): ghost-text completions in every text field.
os_ge 14 && dw write NSGlobalDomain NSAutomaticInlinePredictionEnabled -bool false

# ── Dock, Spaces & windows ──────────────────────────────────────────
dw write com.apple.dock autohide -bool true
dw write com.apple.dock autohide-delay -float 0
dw write com.apple.dock autohide-time-modifier -float 0          # instant show/hide
dw write com.apple.dock show-recents -bool false
dw write com.apple.dock tilesize -int 42
# Keep Spaces in a fixed order (don't reshuffle by most-recent use).
dw write com.apple.dock mru-spaces -bool false
# Sonoma+: clicking the wallpaper hides every window. Limit that to Stage
# Manager, which is where Apple intended it.
os_ge 14 && dw write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false

# ── Panels & documents ──────────────────────────────────────────────
# Save/print panels expanded by default (no more clicking the little arrow).
dw write NSGlobalDomain NSNavPanelExpandedStateForSaveMode  -bool true
dw write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
dw write NSGlobalDomain PMPrintingExpandedStateForPrint  -bool true
dw write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true
# Default new documents to the local disk, not iCloud Drive.
dw write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false
# NOTE: download quarantine (Gatekeeper) is left ENABLED on purpose — this
# box handles untrusted APKs/IPAs/firmware, so keep the safety prompt.

# ── Menu bar ────────────────────────────────────────────────────────
# Battery percentage (Control Center domain, Sonoma+). Laptops only.
# (string match, not `| grep -q`: under pipefail an early grep exit can
# SIGPIPE pmset and turn a match into a failure)
if [[ "$(pmset -g batt 2>/dev/null)" == *InternalBattery* ]]; then
  dw -currentHost write com.apple.controlcenter BatteryShowPercentage -bool true
fi

# ── External disks ──────────────────────────────────────────────────
# Don't offer every newly attached disk/image for Time Machine — constant
# noise when flashing devices or mounting firmware images.
sdw write /Library/Preferences/com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true

# ── Siri: turn it off ───────────────────────────────────────────────
# These disable classic Siri and "Hey Siri". On 15.1+ / 26+ Siri lives under
# "Apple Intelligence & Siri"; Apple Intelligence itself has NO `defaults`
# kill-switch and is turned off in System Settings (guidance at the end).
dw write com.apple.assistant.support "Assistant Enabled" -bool false
dw write com.apple.assistant.support "Siri Enabled" -bool false
dw write com.apple.Siri StatusMenuVisible -bool false
dw write com.apple.Siri VoiceTriggerUserEnabled -bool false        # "Hey Siri"
# 2 = explicitly opted out of "Improve Siri & Dictation" audio sharing.
dw write com.apple.assistant.support "Siri Data Sharing Opt-In Status" -int 2

# ── Apple personalized ads & ad identifier ──────────────────────────
dw write com.apple.AdLib allowApplePersonalizedAdvertising -bool false
dw write com.apple.AdLib allowIdentifierForAdvertising -bool false

# ── Diagnostics & crash reporting ───────────────────────────────────
# HONEST CAVEAT: the authoritative "Share Mac Analytics" / "Share with App
# Developers" switches live in System Settings ▸ Privacy & Security ▸
# Analytics & Improvements, and Apple resists scripting them. These are the
# historical CrashReporter keys; they may need Full Disk Access for this
# terminal and may not move the UI toggle. Verify in the UI.
_diag="/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist"
sdw write "$_diag" AutoSubmit -bool false
sdw write "$_diag" ThirdPartyDataSubmit -bool false
# No "report to Apple?" dialog on crashes (also keeps fuzzing runs quiet).
dw write com.apple.CrashReporter DialogType -string none

# ── Apply (restart affected UI processes) ───────────────────────────
# cfprefsd is deliberately NOT killed: every write above already went
# through it, and killing it can drop other apps' pending writes.
if [[ "${DRY_RUN:-0}" != "1" ]]; then
  for app in Finder Dock SystemUIServer ControlCenter WindowManager Siri; do
    killall "$app" >/dev/null 2>&1 || true
  done
fi

if [[ "$DW_FAILED" -gt 0 ]]; then
  warn "$DW_FAILED defaults write(s) failed (see above) — the rest were applied."
else
  ok "macOS defaults applied."
fi
info "Log out/in for keyboard repeat, text substitution and Siri changes to take effect."

# ── Version-aware privacy guidance (these toggles are UI-only) ──────
# Pane-level instructions on purpose: Apple renames individual toggles
# between releases, the panes are stable.
warn "Finish these by hand in System Settings (not reliably scriptable):"
warn "  • Privacy & Security ▸ Analytics & Improvements ▸ turn OFF every toggle"
if os_ge 26; then
  warn "  • Apple Intelligence & Siri ▸ turn OFF Apple Intelligence and Siri"
  warn "  • Apple Intelligence & Siri ▸ per-app 'Learn from this app' OFF, if shown"
elif os_ge 15; then
  warn "  • Apple Intelligence & Siri (15.1+) ▸ turn OFF Apple Intelligence and Siri"
else
  warn "  • Siri & Spotlight ▸ disable Siri"
fi
