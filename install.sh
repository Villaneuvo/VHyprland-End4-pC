#!/usr/bin/env bash
# Rebuild this Hyprland + illogical-impulse + end4-pC desktop on a fresh Ubuntu 26.04 (x86_64).
#
#   ./install.sh          everything (run from a terminal inside your normal GNOME session, as your user)
#   ./install.sh files    only copy the config files from home/ (after pulling repo changes)
#
# Each step skips work that is already done, so re-running is safe.
# Known-good versions are pinned; override with DOTS_REF=main / END4_REF=main to try newer ones.
set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd)
DOTS=$HOME/dots-hyprland
END4=$HOME/.config/quickshell/end4-pC
SRC=$HOME/src
DOTS_REF=${DOTS_REF:-2f2a376fdb2ad738bf55f693dd0b474b64bb0ab8}   # dots-hyprland, tested 2026-10-13
END4_REF=${END4_REF:-96b45aaf6ca5a439812f60e508775a0a1e954b63}   # end4-pC, tested 2026-10-15
MATUGEN_VER=4.2.0
ADW_GTK3_VER=v6.5
DARKLY_VER=0.5.41
NERD_FONTS_VER=v3.5.1
MPVPAPER_VER=1.9
NWG_DISPLAYS_VER=v0.4.4

log()  { printf '\n\033[1;35m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mxx %s\033[0m\n' "$*"; exit 1; }

check_system() {
    [ "$(id -u)" -ne 0 ] || die "Run as your normal user, not root (sudo is used where needed)."
    . /etc/os-release
    [ "${VERSION_ID:-}" = "26.04" ] || warn "Made for Ubuntu 26.04, this is ${PRETTY_NAME:-unknown}. Continuing anyway."
    [ "$(uname -m)" = x86_64 ] || die "x86_64 only."
    [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || warn "No desktop session bus: run this from a terminal inside your graphical session."
    sudo -v
}

add_ppas() {
    log "Adding PPAs (Hyprland >= 0.55, SongRec)"
    sudo install -d -m 755 /etc/apt/keyrings
    # Keys verified against each PPA's signed InRelease (fingerprints in README.md)
    sudo install -m 644 "$REPO/keys/cppiber-hyprland.gpg" "$REPO/keys/marin-m-songrec.gpg" /etc/apt/keyrings/
    local ppa
    for ppa in cppiber/hyprland marin-m/songrec; do
        # Same file names add-apt-repository would use, so re-runs don't duplicate sources
        printf 'Types: deb\nURIs: https://ppa.launchpadcontent.net/%s/ubuntu/\nSuites: resolute\nComponents: main\nSigned-By: /etc/apt/keyrings/%s.gpg\n' \
            "$ppa" "${ppa%/*}-${ppa#*/}" | sudo tee "/etc/apt/sources.list.d/${ppa%/*}-ubuntu-${ppa#*/}-resolute.sources" >/dev/null
    done
}

apt_packages() {
    log "Installing apt packages"
    # The PPA's libudis86.1 ships the same .so as Ubuntu's libudis86-0 without declaring Replaces
    if dpkg -s libudis86-0 >/dev/null 2>&1; then
        sudo dpkg -r libudis86-dev libudis86-0 || warn "Could not remove libudis86-0; the install below may fail on it."
    fi
    sudo apt-get update
    # shellcheck disable=SC2046
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y $(grep -vE '^\s*(#|$)' "$REPO/packages.txt")
}

clone_at() {  # clone_at <url> <dir> <ref>
    [ -d "$2/.git" ] || git clone "$1" "$2"
    git -C "$2" fetch -q --all --tags || true
    git -C "$2" checkout -q "$3"
}

build_quickshell() {
    local commit
    commit=$(grep -oP "^_commit='\K[0-9a-f]+" "$DOTS/sdata/dist-arch/illogical-impulse-quickshell-git/PKGBUILD")
    if command -v qs >/dev/null && qs --version | grep -q "$commit"; then log "Quickshell $commit already installed"; return; fi
    log "Building Quickshell at $commit (pinned by dots-hyprland)"
    mkdir -p "$SRC"
    clone_at https://git.outfoxxed.me/quickshell/quickshell.git "$SRC/quickshell" "$commit"
    # INSTALL_QML_PREFIX: Ubuntu's QML path. CRASH_HANDLER=OFF: cpptrace isn't packaged on Ubuntu
    (cd "$SRC/quickshell" &&
        cmake -GNinja -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=/usr \
            -DINSTALL_QML_PREFIX=lib/x86_64-linux-gnu/qt6/qml -DCRASH_HANDLER=OFF -DDISTRIBUTOR="Ubuntu (manual build)" &&
        cmake --build build && sudo cmake --install build)
}

user_tools() {
    log "Installing uv, matugen, fonts, GTK/Qt themes"
    command -v uv >/dev/null || [ -x "$HOME/.local/bin/uv" ] || curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"

    matugen --version 2>/dev/null | grep -q "$MATUGEN_VER" ||
        curl -L "https://github.com/InioX/matugen/releases/download/v$MATUGEN_VER/matugen-$MATUGEN_VER-x86_64.tar.gz" |
        sudo tar -xz -C /usr/local/bin matugen

    local f=$HOME/.local/share/fonts/ii-extra
    if [ ! -f "$f/ReadexPro.ttf" ]; then
        mkdir -p "$f"
        curl -Lo "$f/MaterialSymbolsRounded.ttf"  "https://github.com/google/material-design-icons/raw/master/variablefont/MaterialSymbolsRounded%5BFILL,GRAD,opsz,wght%5D.ttf"
        curl -Lo "$f/MaterialSymbolsOutlined.ttf" "https://github.com/google/material-design-icons/raw/master/variablefont/MaterialSymbolsOutlined%5BFILL,GRAD,opsz,wght%5D.ttf"
        curl -Lo "$f/Rubik.ttf"     "https://github.com/google/fonts/raw/main/ofl/rubik/Rubik%5Bwght%5D.ttf"
        curl -Lo "$f/ReadexPro.ttf" "https://github.com/google/fonts/raw/main/ofl/readexpro/ReadexPro%5BHEXP,wght%5D.ttf"
        curl -L "https://github.com/ryanoasis/nerd-fonts/releases/download/$NERD_FONTS_VER/JetBrainsMono.tar.xz" | tar -xJ -C "$f" --wildcards '*.ttf'
        fc-cache -f
    fi

    [ -d "$HOME/.local/share/themes/adw-gtk3" ] || {
        mkdir -p "$HOME/.local/share/themes"
        curl -L "https://github.com/lassekongo83/adw-gtk3/releases/download/$ADW_GTK3_VER/adw-gtk3$ADW_GTK3_VER.tar.xz" | tar -xJ -C "$HOME/.local/share/themes"
    }

    dpkg -s darkly >/dev/null 2>&1 || {
        local deb=/tmp/darkly-$DARKLY_VER.deb
        curl -Lo "$deb" "https://github.com/Bali10050/Darkly/releases/download/v$DARKLY_VER/darkly-${DARKLY_VER}_kubuntu-26.04_amd64.deb"
        sudo apt-get install -y "$deb"
    }
}

install_ii() {
    log "Installing illogical-impulse (dots-hyprland @ ${DOTS_REF:0:7})"
    clone_at https://github.com/end-4/dots-hyprland.git "$DOTS" "$DOTS_REF"
    # Its installer forces a broken Nix route on Debian/Ubuntu; a local os-release (gitignored upstream)
    # makes it treat us like Arch, and --skip-alldeps skips Arch packaging (apt did the deps).
    printf 'ID=arch\n' > "$DOTS/os-release"
    (cd "$DOTS" && ./setup install --skip-alldeps -f)
    # Ubuntu's Qt 6.10 has no FluentWinUI3 style; ii fails to load without this
    sed -i '/^import QtQuick.Controls.FluentWinUI3$/d' "$HOME/.config/quickshell/ii/modules/waffle/looks/WTextField.qml"
}

install_end4pc() {
    log "Installing end4-pC @ ${END4_REF:0:7}"
    clone_at https://github.com/pctrade/end4-pC.git "$END4" "$END4_REF"
    # Qt 6.10's QML parser rejects a variable named `double` (custom/scripts/end4pc-qt610-fix.sh re-applies this at login)
    sed -i -E 's/\bvar double\b/var dbl/; s/\) double = (true|false)/) dbl = \1/g; s/if \(double\)/if (dbl)/' \
        "$END4/modules/ii/background/widgets/images/ImageCardWidget.qml"
}

copy_files() {
    log "Copying config files from home/"
    local backup p
    backup=$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)
    while IFS= read -r p; do
        [[ -z $p || $p == \#* ]] && continue
        [ -e "$REPO/home/$p" ] || { warn "not in repo, skipped: $p"; continue; }
        if [ -e "$HOME/$p" ]; then
            mkdir -p "$backup/$(dirname "$p")"
            cp -a "$HOME/$p" "$backup/$p"
        fi
        mkdir -p "$HOME/$(dirname "$p")"
        if [ -d "$REPO/home/$p" ]; then
            mkdir -p "$HOME/$p"
            cp -a "$REPO/home/$p/." "$HOME/$p/"
        else
            cp -a "$REPO/home/$p" "$HOME/$p"
        fi
        # sync.sh stored this machine's home path as @HOME@
        { grep -rlI '@HOME@' "$HOME/$p" 2>/dev/null || true; } | xargs -r sed -i "s|@HOME@|$HOME|g"
    done < "$REPO/manifest.txt"
    [ -d "$backup" ] && echo "Previous versions of replaced files: $backup"
    chmod +x "$HOME"/.config/hypr/custom/scripts/* 2>/dev/null || true
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
}

desktop_tweaks() {
    log "Desktop tweaks"
    # end4-pC sometimes fails to write its "greeted" marker and then resets the wallpaper on every boot
    mkdir -p "$HOME/.local/state/quickshell/user"
    echo "This file is just here to confirm you've been greeted :>" > "$HOME/.local/state/quickshell/user/first_run.txt"
    # Services that fight end4-pC (or duplicate ii's autostart) when started via graphical-session.target
    systemctl --user mask waybar.service swaync.service hypridle.service hyprsunset.service 2>/dev/null || true
    # KDE apps (Dolphin "Open with") look for plasma-applications.menu, which only Plasma ships
    mkdir -p "$HOME/.config/menus"
    ln -sf /etc/xdg/menus/gnome-applications.menu "$HOME/.config/menus/plasma-applications.menu"
    command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true

    # Intel iGPU + NVIDIA dGPU: stable /dev/dri/*-gpu names for AQ_DRM_DEVICES (custom/env.lua)
    local igpu dgpu
    igpu=$(lspci -D -d ::03xx | awk '/Intel/{print $1; exit}')
    dgpu=$(lspci -D -d ::03xx | awk '/NVIDIA/{print $1; exit}')
    if [ -n "$igpu" ] && [ -n "$dgpu" ]; then
        printf 'KERNEL=="card*", KERNELS=="%s", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", SYMLINK+="dri/intel-igpu"\nKERNEL=="card*", KERNELS=="%s", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", SYMLINK+="dri/nvidia-dgpu"\n' \
            "$igpu" "$dgpu" | sudo tee /etc/udev/rules.d/61-hypr-gpu.rules >/dev/null
        sudo udevadm control --reload && sudo udevadm trigger --subsystem-match=drm
        echo "Hybrid GPU: Hyprland renders on the Intel iGPU ($igpu), NVIDIA ($dgpu) stays available."
    fi
}

extras() {
    log "fisher + nvm.fish, nwg-displays, mpvpaper"
    # fisher plugins live in ~/.local/share/fisher (see conf.d/fisher-path.fish): dots-hyprland wipes ~/.config/fish/functions
    if [ ! -f "$HOME/.local/share/fisher/functions/nvm.fish" ]; then
        fish -c 'curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher jorgebucaran/nvm.fish'
    fi
    local node
    node=$(sed -n 's/^set -g nvm_default_version //p' "$HOME/.config/fish/conf.d/fisher-path.fish")
    [ -n "$node" ] && fish -c "nvm install $node" >/dev/null

    # nwg-displays from PyPI/git: Ubuntu's 0.3.x can't write Hyprland's Lua config
    local venv=$HOME/.local/share/nwg-displays-venv
    [ -x "$venv/bin/nwg-displays" ] || {
        python3 -m venv --system-site-packages "$venv"
        "$venv/bin/pip" install -q "git+https://github.com/nwg-piotr/nwg-displays@$NWG_DISPLAYS_VER" i3ipc
    }

    command -v mpvpaper >/dev/null || {
        mkdir -p "$SRC"
        clone_at https://github.com/GhostNaN/mpvpaper.git "$SRC/mpvpaper" "$MPVPAPER_VER"
        (cd "$SRC/mpvpaper" && meson setup build --prefix=/usr/local --wipe >/dev/null && ninja -C build && sudo ninja -C build install)
    }
}

case "${1:-all}" in
    files)
        copy_files ;;
    all)
        check_system
        add_ppas
        apt_packages
        clone_at https://github.com/end-4/dots-hyprland.git "$DOTS" "$DOTS_REF"
        build_quickshell
        user_tools
        install_ii
        install_end4pc
        copy_files
        desktop_tweaks
        extras
        log "Done"
        cat <<'EOF'
Next:
  1. Log out. On the login screen pick the "Hyprland" session (NOT "Hyprland (uwsm-managed)").
  2. Wallpaper, colors and widgets come from the himeko preset; Super+Esc opens end4-pC settings.
  3. Super+Alt+P: display modes · "Display Settings" in the launcher: monitor layout + primary display.
  4. AI sidebar keys (Gemini etc.) are stored in the keyring, not in this repo: set them again with /key.
EOF
        ;;
    *) die "usage: $0 [all|files]" ;;
esac
