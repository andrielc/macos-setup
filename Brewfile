# ╔══════════════════════════════════════════════════════════════════╗
# ║   Brewfile :: core  —  mobile developer toolkit                    ║
# ╚══════════════════════════════════════════════════════════════════╝
# Install with:  brew bundle --file=Brewfile
#
# All names below were verified against `brew info` on 2026-10-12.

# ── Taps ────────────────────────────────────────────────────────────
# (homebrew/services is built into brew now; the tap is empty)
tap "nohajc/anylinuxfs"

# ══ FORMULAE ════════════════════════════════════════════════════════

# ── Core CLI / shell quality-of-life ────────────────────────────────
brew "coreutils"          # GNU core utils (gls, etc.)
brew "gnu-sed"            # gsed / sed
brew "gnu-tar"            # gtar / tar
brew "findutils"          # gfind, gxargs
brew "grep"              # GNU grep
brew "wget"
brew "aria2"             # multi-connection downloader
brew "curl"
brew "git"
brew "git-lfs"
brew "git-delta"         # nicer git diffs (GIT_PAGER in zshrc)
brew "gh"               # GitHub CLI
brew "lazygit"
brew "jq"
brew "yq"
brew "ripgrep"
brew "fd"
brew "fzf"
brew "zoxide"
brew "bat"
brew "eza"
brew "btop"
brew "htop"
brew "tree"
brew "tmux"
brew "neovim"
brew "parallel"
brew "watch"
brew "minicom"           # serial console
brew "sshpass"
brew "xz"               # unxz (used by scripts/frida-server.sh)
brew "zsh-autosuggestions"
brew "zsh-syntax-highlighting"

# ── Build toolchain ─────────────────────────────────────────────────
brew "cmake"
brew "ninja"
brew "pkgconf"
brew "bazel"
brew "create-dmg"

# ── Language runtimes / package managers ────────────────────────────
brew "node"
brew "php"
brew "go"
brew "rustup"            # keg-only: run `"$(brew --prefix rustup)/bin/rustup-init"`
                         #   after install to create a ~/.cargo toolchain
brew "uv"               # Python tool/venv manager (frida, objection, etc.)
brew "pipx"             # alt isolated python CLIs
brew "cocoapods"        # iOS dependency manager
brew "openjdk@17"       # primary JDK (installer symlinks into java_home)
brew "openjdk@21"
brew "openjdk@11"       # legacy, some reversing tools still want it
brew "python@3.14"      # installer symlinks python/python3 -> this in ~/.local/bin
brew "mas"              # Mac App Store CLI (Xcode, etc.)
brew "repo"             # Android `repo` (AOSP multi-git tool)

# ── Android: reversing / repackaging / analysis ─────────────────────
brew "apktool"
# jadx moved to the git toolkit (scripts/tools-sync.sh -> ~/tools/jadx;
# build with `./gradlew dist`). Re-add here if you want the ready binary.
brew "dex2jar"
brew "bundletool"       # .aab -> apks
# smali/baksmali ship inside the Android SDK build-tools (added to PATH)
brew "simg2img"         # sparse <-> raw android images
brew "erofs-utils"      # EROFS (modern android system partitions)
brew "e2fsprogs"        # ext2/3/4
brew "libsepol"         # SELinux policy (sepolicy work)

# ── iOS: device / IPA / firmware ────────────────────────────────────
brew "libimobiledevice" # ideviceinfo, idevice_id, etc.
brew "ideviceinstaller"
brew "ios-deploy"
brew "ipatool"          # pull IPAs from App Store
brew "ipsw"             # iOS firmware tooling
brew "ldid"             # codesign / entitlements

# ── Reverse engineering / binary analysis ───────────────────────────
brew "radare2"
brew "ghidra"           # NSA RE suite
brew "binwalk"          # firmware carving
brew "exiftool"
brew "poppler"          # pdf tooling (pdfimages, etc.)
brew "tesseract"        # OCR

# ── Network / pentest ───────────────────────────────────────────────
brew "nmap"
brew "rustscan"         # fast port scanner (feeds nmap)
brew "mitmproxy"        # HTTPS intercept (CLI; also a cask available)
brew "libpcap"
brew "unbound"          # local DNS resolver

# ── Crypto / passwords ──────────────────────────────────────────────
brew "hashcat"

# ── SAST ────────────────────────────────────────────────────────────
brew "semgrep"

# ── Virtualization / emulation ──────────────────────────────────────
brew "qemu"

# ── Media (dependencies for various tooling) ────────────────────────
brew "ffmpeg"
brew "graphviz"
brew "sevenzip"         # 7z

# ── DB clients ──────────────────────────────────────────────────────
brew "mysql-client"

# ── Misc from the reference machine ─────────────────────────────────
brew "qt"               # Qt (GUI toolkit; dependency of several RE tools)
brew "nohajc/anylinuxfs/anylinuxfs"   # mount Linux filesystems via a VM

# ══ CASKS ═══════════════════════════════════════════════════════════

# ── Terminal / editors / IDEs ───────────────────────────────────────
cask "ghostty"
cask "visual-studio-code"
cask "sublime-text"
cask "cursor"

# ── Browsers (proxied) ──────────────────────────────────────────────
cask "firefox"
cask "brave-browser"
cask "google-chrome"
cask "tor-browser"

# ── Mobile: Android ─────────────────────────────────────────────────
cask "android-studio"
cask "android-commandlinetools"   # sdkmanager (installer drives this)
# NOTE: adb/fastboot come from the SDK's platform-tools (installed by
# scripts/android.sh). The standalone `android-platform-tools` cask is
# intentionally omitted to avoid two adb versions fighting ("adb server
# version doesn't match this client").
cask "scrcpy"                     # screen mirror/control

# ── Mobile: iOS ─────────────────────────────────────────────────────
cask "iexplorer"

# ── Reversing / app analysis GUIs ───────────────────────────────────
cask "burp-suite"                 # community (see README for Pro)
cask "jd-gui"                     # java decompiler GUI
cask "hex-fiend"                  # hex editor
cask "db-browser-for-sqlite"
cask "dbeaver-community"
cask "wireshark-app"              # (renamed from `wireshark`)
cask "utm"                        # qemu-based VMs (apple silicon friendly)

# ── API / HTTP clients ──────────────────────────────────────────────
cask "bruno"
cask "insomnia"
cask "postman"

# ── Network / VPN ───────────────────────────────────────────────────
cask "little-snitch"              # outbound firewall
cask "mullvad-vpn"
cask "openvpn-connect"

# ── Crypto / keys ───────────────────────────────────────────────────
cask "gpg-suite"
cask "yubico-authenticator"

# ── Diff / archive / screenshots / system ──────────────────────────
cask "meld"
cask "keka"
cask "shottr"
cask "flameshot"
cask "stats"                      # menubar system monitor

# ── Containers ──────────────────────────────────────────────────────
cask "docker-desktop"             # (renamed from `docker`)

# ── Oracle JDK (matches the reference machine's primary JDK) ────────
# java_home picks the newest registered JDK; this restores Oracle JDK as
# the default over openjdk@17/@21. Requires accepting Oracle's license.
cask "oracle-jdk"
cask "oracle-jdk-javadoc"

# ── Fonts (nerd fonts for terminal glyphs) ──────────────────────────
cask "font-jetbrains-mono-nerd-font"
cask "font-hack-nerd-font"
cask "font-meslo-lg-nerd-font"
cask "font-3270-nerd-font"
