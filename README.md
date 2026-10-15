# macOS Setup

Automated, idempotent setup for a Mac. Installs and configures the toolkit for Android/iOS app reversing, instrumentation, and network interception — plus a portable, cleaned-up `zsh` config.

Targets Apple Silicon on macOS 15 and later. Intel Macs are supported on a best-effort basis (macOS 26 is the last Intel release); Apple-Silicon-only steps are skipped automatically.

## Quick start

On a truly fresh Mac, install the Command Line Tools first (gives you `git`):

```bash
xcode-select --install   # or just run ./install.sh, which does this too
```

```bash
git clone https://github.com/<your-user>/macos-setup.git ~/macos-setup && cd ~/macos-setup

# See exactly what would happen — changes nothing:
./install.sh --dry-run

# Full run (core toolkit):
./install.sh
```

Open a new terminal (or `exec zsh`) when it finishes.

## What it does

`install.sh` runs these steps, in order. Each is idempotent and re-runnable:

| Step       | Action |
|------------|--------|
| `clt`      | Xcode Command Line Tools (waits for the async install to finish) |
| `rosetta`  | Rosetta 2 (Apple Silicon only) |
| `homebrew` | Installs Homebrew non-interactively, loads it into the session |
| `brew`     | `brew bundle` the core [`Brewfile`](Brewfile); symlinks brew's JDK so `java_home` finds it |
| `dotfiles` | Backs up then symlinks `~/.zshrc`; seeds `~/.zshrc.local`; clones zsh plugins as a fallback |
| `gitconfig`| Sets git identity from a prompt or `GIT_NAME`/`GIT_EMAIL` (never hardcoded) |
| `python`   | Installs frida-tools, objection, apkleaks, androguard via `uv` (mitmproxy comes from Homebrew) |
| `android`  | Installs the newest **stable** platform, build-tools, NDK, CMake + emulator image via `sdkmanager` (rc/beta filtered out; override with `NDK_PKG=…` etc.) |
| `macos`    | Applies sensible macOS defaults (Finder, screenshots, keyboard, Dock) |

With `--tools`, a final (opt-in) step git-clones the `~/tools` toolkit — see
[Tools (git clones)](#tools-git-clones) below.

### Flags

```
--dry-run           print actions, change nothing
--only  a,b,c       run only these steps
--skip  a,b,c       run everything except these
--tools             also git-clone the ~/tools toolkit (clone-only)
--v8                also fetch V8 source via depot_tools (multi-GB, no build)
--help
```

Every run is logged to `logs/install-<timestamp>.log`.

## The zsh config

[`dotfiles/zshrc`](dotfiles/zshrc) is a portable, fast-starting shell config:

- **Homebrew loaded first** via `brew shellenv`, so brew tools win over system
  BSD utilities.
- **No hardcoded versions.** Java is resolved with `/usr/libexec/java_home`;
  the newest Android **build-tools** and **NDK** are picked with a glob.
- **No subshell on startup** — uses `$HOME/go/bin` instead of `$(go env GOPATH)`.
- Uses Android `cmdline-tools/latest/bin` + `emulator` (not the deprecated
  `$ANDROID_HOME/tools`).
- `typeset -U path` de-dupes `PATH`; `compinit` dump cached (faster startup).
- zsh plugins sourced from the brew prefix, falling back to `~/.zsh`.
- Machine-specific `PATH` entries and secrets moved to **`~/.zshrc.local`**
  (not tracked). See [`dotfiles/zshrc.local.example`](dotfiles/zshrc.local.example).
- Mobile-dev aliases/functions added: `adbr`, `pullapk`, `fps`/`fpsi`, `idev`, …

Interactive startup is roughly 70–90 ms on an M-series Mac.

## Mobile-dev helpers

```bash
# Download the frida-server matching your installed frida client and push
# it to a connected Android device (auto-detects the device ABI):
scripts/frida-server.sh

# Pull an installed APK off a device by package name (zsh function):
pullapk com.example.app      # -> ./com.example.app.apk
```

## Tools (git clones)

A curated set of mobile / RE / recon tools lives as **git clones under `~/tools`**
rather than Homebrew formulae. [`scripts/tools-sync.sh`](scripts/tools-sync.sh)
clones and updates them:

```bash
scripts/tools-sync.sh                 # clone/update everything into ~/tools
scripts/tools-sync.sh --list          # show the manifest
scripts/tools-sync.sh --only ffuf,angr
scripts/tools-sync.sh --skip SecLists,nuclei-templates
scripts/tools-sync.sh --full          # keep full history (default: shallow)
scripts/tools-sync.sh --dry-run
./install.sh --tools                  # same step, as part of a full run
```

- **Source-only.** It `git clone`s / `git pull`s; it does **not** build. Each tool
  is then built in its own way (Python venv, `go build`, `cargo build`,
  `./gradlew dist`, …) — the script prints the per-language hints at the end.
- **Idempotent & non-destructive.** An existing clone is fast-forwarded; a
  non-git folder of the same name already in `~/tools` is left untouched.
- **Shallow by default** (`--depth=1`) to keep big repos (SecLists,
  nuclei-templates) small; pass `--full` for history.
- Homebrew still provides the runtimes, libraries, and GUI apps that can't
  sensibly be built from source (`go`, `python`, `openjdk`, `radare2`, casks, …).

### Android GKI kernel source

Pull the newest GKI release branch of the Android kernel into `kernel-repo/` with the AOSP `repo`
tool (not part of the default install — it's a multi-GB download):

```bash
./scripts/kernel-sync.sh                 # newest common-androidNN-X.Y (full)
./scripts/kernel-sync.sh -b common-android-mainline   # dev branch tracking upstream
./scripts/kernel-sync.sh --shallow       # --depth=1, smaller/faster, no history
./scripts/kernel-sync.sh -b common-android15-6.6   # a specific GKI release
```

The synced tree is git-ignored. See [`kernel-repo/README.md`](kernel-repo/README.md).

### V8 + Fuzzilli

[`scripts/v8-sync.sh`](scripts/v8-sync.sh) bootstraps Chromium's `depot_tools`
(full clone at `~/tools/depot_tools`), then `fetch v8` into `~/tools/v8/v8`;
re-runs update it with `gclient sync`. Fuzzilli is a regular `tools-sync.sh`
entry (`~/tools/fuzzilli`).

```bash
./scripts/v8-sync.sh                     # fetch / update V8 (origin/main)
./scripts/v8-sync.sh --shallow           # first fetch with --no-history
./scripts/v8-sync.sh -r origin/14.2-lkgr # a specific ref / branch / commit
./scripts/v8-sync.sh --build             # + release d8 -> out/<cpu>.release
./scripts/v8-sync.sh --fuzzilli          # + Fuzzilli d8 (out/fuzzbuild) + build Fuzzilli
```

- **Building needs full Xcode** (not just the CLT). The script checks `xcode-select -p`.
- Fuzzilli's own `Targets/V8/fuzzbuild.sh` is Linux-only now, so the script
  runs the same `gn` args itself with the host CPU (`arm64` on Apple Silicon).
- Fuzzilli's `Package.swift` pins a minimum Swift version that can be newer than
  the one bundled with Xcode. The script checks this first and points to
  `swiftly` if your toolchain is too old.

### frida

The frida **client and server versions must match**. `python-tools.sh` can pin
the client to the version in a `FRIDA_VERSION` file (if present) and otherwise
records whatever it installed into that file. `frida-server.sh` then reads the
**installed client's** `frida --version` directly and downloads the exact
matching server, so the two never drift apart.

## Manual steps (cannot be automated)

These need a license, an account, or aren't on Homebrew:

- **Full Xcode** — App Store (`mas install 497799835`) or developer.apple.com
- **Burp Suite Professional**, **IDA Pro**, **JEB** — licensed installers
- **Sideloadly** — <https://sideloadly.io>
- **PixelFlasher** — <https://github.com/badabing2005/PixelFlasher>
- **Bytecode-Viewer** — <https://bytecodeviewer.com>

## Safety notes

- Existing dotfiles are **backed up** (`.bak.<timestamp>`) before being replaced —
  nothing is clobbered silently.
- `--dry-run` shows every action first.
- Downloaded firmware/APKs are untrusted — keep them in their own directory.
- Review [`scripts/macos-defaults.sh`](scripts/macos-defaults.sh) before running;
  comment out any default you don't want.
- Personal config (`~/.zshrc.local`, git identity) is never committed — only the
  `*.example` templates are tracked.

## Disclaimer

The reverse-engineering and instrumentation tools installed here are intended for
security research, CTFs, and testing on apps and devices you own or are
authorized to test. Provided as-is, without warranty; use at your own risk.

## Layout

```
install.sh                 orchestrator (flags, logging, sudo keepalive)
Brewfile                   core formulae + casks
dotfiles/
  zshrc                    the portable shell config
  zshrc.local.example      machine-specific PATHs/secrets template
  gitconfig.example        git config template
scripts/
  lib.sh                   shared helpers (logging, backup+symlink)
  android.sh               sdkmanager components
  python-tools.sh          frida/objection/etc. via uv
  frida-server.sh          version-matched frida-server deploy
  tools-sync.sh            git-clone the ~/tools toolkit (clone-only)
  kernel-sync.sh           sync Android GKI kernel source via `repo`
  v8-sync.sh               depot_tools + V8 fetch/sync, optional d8 / Fuzzilli builds
  macos-defaults.sh        macOS defaults
kernel-repo/               destination for the GKI kernel source (git-ignored)
```
