#!/usr/bin/env bash
# Replicate this Arch + Hyprland setup on a fresh archinstall system.
# Usage: ./install.sh                 menu: pick modules, confirm once, run unattended
#        ./install.sh rice dev        run only these modules
#        ./install.sh plugins         after the first Hyprland login (needs a running session)
# Modules: packages rice system dev plugins. Safe to re-run.
set -euo pipefail

REPO=$(dirname "$(realpath "$0")")
BACKUP=$HOME/.config-backup-$(date +%F-%H%M%S)
MODULES=(packages rice system dev)
MACSHELL_URL=https://github.com/Azriel-Fajar/MacShell.git
MACSHELL_BRANCH=azriel
HYPRGLASS_URL=https://github.com/Azriel-Fajar/hyprglass.git
HYPRGLASS_BRANCH=macshell

log()  { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# Read a package list, skipping comments and blank lines
pkglist() { grep -vE '^\s*(#|$)' "$REPO/packages/$1"; }

# Symlink a repo path into $HOME; anything already there is moved to $BACKUP
link() {
    local src=$REPO/$1 dst=$2
    [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(realpath "$src")" ] && return
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        mkdir -p "$(dirname "$BACKUP/${dst#"$HOME"/}")"
        mv "$dst" "$BACKUP/${dst#"$HOME"/}"
        echo "  backed up $dst"
    fi
    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
    echo "  $dst -> $src"
}

clone_or_pull() {  # clone_or_pull <url> <branch> <dir>
    if [ -d "$3/.git" ]; then
        git -C "$3" pull --ff-only || warn "$3: pull failed, keeping local state"
    else
        [ -e "$3" ] && { mkdir -p "$BACKUP"; mv "$3" "$BACKUP/"; }
        git clone -b "$2" "$1" "$3"
    fi
}

aur_helper() {
    command -v yay >/dev/null && { echo yay; return; }
    command -v paru >/dev/null && { echo paru; return; }
    log "Bootstrapping yay" >&2
    local tmp; tmp=$(mktemp -d)
    git clone https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin" >&2
    (cd "$tmp/yay-bin" && makepkg -si --noconfirm >&2)
    echo yay
}

gpu_packages() {
    local gpus; gpus=$(lspci | grep -Ei 'vga|3d|display')
    grep -q GenuineIntel /proc/cpuinfo && echo intel-ucode
    grep -q AuthenticAMD /proc/cpuinfo && echo amd-ucode
    echo mesa lib32-mesa
    grep -q Intel <<<"$gpus" && echo vulkan-intel lib32-vulkan-intel intel-media-driver libva-intel-driver
    grep -qE 'AMD|ATI|Radeon' <<<"$gpus" && echo vulkan-radeon lib32-vulkan-radeon
    grep -qi nvidia <<<"$gpus" && echo nvidia-open nvidia-utils lib32-nvidia-utils libva-nvidia-driver
    true
}

mod_packages() {
    log "Enabling multilib"
    if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
        sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf
    fi
    sudo sed -i 's/^#Color/Color/' /etc/pacman.conf

    log "Installing official packages"
    sudo pacman -Syu --noconfirm
    local available missing
    available=$(pacman -Slq | sort -u)
    missing=$(comm -23 <(pkglist pacman.txt | sort -u) - <<<"$available")
    [ -n "$missing" ] && warn "Not in the repos anymore, skipped: $(echo $missing)"
    comm -12 <(pkglist pacman.txt | sort -u) - <<<"$available" \
        | sudo pacman -S --needed --noconfirm -

    log "Installing CPU microcode and GPU drivers"
    # shellcheck disable=SC2046
    sudo pacman -S --needed --noconfirm $(gpu_packages)

    log "Installing AUR packages"
    local helper; helper=$(aur_helper)
    pkglist aur.txt | "$helper" -S --needed --noconfirm - || warn "Some AUR packages failed, re-run ./install.sh packages"

    if [ -s "$REPO/packages/flatpak.txt" ]; then
        log "Installing flatpaks"
        flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        pkglist flatpak.txt | xargs -r flatpak install --user -y flathub
    fi
}

mod_rice() {
    log "Linking desktop configs"
    local d
    for d in hypr macbar macdock matugen rofi kitty wlogout gtk-3.0 mako environment.d; do
        link "config/$d" "$HOME/.config/$d"
    done

    # Per-device and generated files: the repo gitignores these
    [ -e "$REPO/config/hypr/monitors.conf" ] || echo 'monitor = , preferred, auto, 1' > "$REPO/config/hypr/monitors.conf"

    log "Installing MacShell"
    mkdir -p "$HOME/.config/quickshell"
    clone_or_pull "$MACSHELL_URL" "$MACSHELL_BRANCH" "$HOME/.config/quickshell/MacShell"

    log "Installing cursor theme"
    mkdir -p "$HOME/.local/share/icons"
    rsync -a "$REPO/assets/icons/" "$HOME/.local/share/icons/"

    log "Building MacOS-Like icon theme (on top of MacTahoe)"
    local src=$HOME/.local/src/MacOS-Like
    clone_or_pull https://github.com/Scrimas/MacOS-Like.git main "$src"
    # "n" declines the optional matugen folder tint
    (cd "$src" && ./setup.sh < <(yes n)) || warn "Icon theme build failed; re-run $src/setup.sh"

    log "Default wallpaper and colors"
    local walls=$HOME/Pictures/Wallpapers state=$HOME/.cache/current-wallpaper
    mkdir -p "$walls" "$HOME/Pictures/Screenshot" "$HOME/.cache" "$HOME/.config/waybar" "$HOME/.config/dunst"
    if [ -z "$(find "$walls" -maxdepth 1 -type f | head -1)" ]; then
        python - "$walls/wallpaper.png" <<'EOF'
import sys
from PIL import Image
w, h = 1920, 1080
top, bottom = (28, 32, 64), (86, 52, 112)
img = Image.new("RGB", (1, h))
for y in range(h):
    t = y / (h - 1)
    img.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
img.resize((w, h)).save(sys.argv[1])
EOF
    fi
    [ -f "$(cat "$state" 2>/dev/null)" ] || find "$walls" -maxdepth 1 -type f | sort | head -1 > "$state"
    matugen image "$(cat "$state")" -m dark </dev/null >/dev/null || warn "matugen failed; colors.conf missing until you pick a wallpaper"

    xdg-user-dirs-update 2>/dev/null || true
}

mod_system() {
    log "User groups"
    local g
    for g in video audio wheel wireshark; do
        getent group "$g" >/dev/null && sudo usermod -aG "$g" "$USER"
    done

    log "zram"
    sudo tee /etc/systemd/zram-generator.conf >/dev/null <<'EOF'
[zram0]
zram-size = min(ram / 2, 4096)
compression-algorithm = zstd
EOF

    log "SDDM macos theme"
    # sddm/install.sh backs up the existing theme.conf, so one must exist
    sudo install -d /etc/sddm.conf.d
    [ -e /etc/sddm.conf.d/theme.conf ] || printf '[Theme]\n' | sudo tee /etc/sddm.conf.d/theme.conf >/dev/null
    "$REPO/config/hypr/sddm/install.sh"

    log "Enabling services"
    local unit
    for unit in NetworkManager bluetooth power-profiles-daemon avahi-daemon systemd-timesyncd fstrim.timer; do
        sudo systemctl enable "$unit" || warn "could not enable $unit"
    done
    # --force takes display-manager.service over from another DM (gdm, lightdm, ly)
    sudo systemctl enable --force sddm || warn "could not enable sddm"
}

mod_dev() {
    log "Linking shell and app configs"
    link home/.bashrc "$HOME/.bashrc"
    link home/.bash_profile "$HOME/.bash_profile"
    link home/.zshrc "$HOME/.zshrc"
    link home/.blerc "$HOME/.blerc"
    link config/starship.toml "$HOME/.config/starship.toml"
    link config/atuin "$HOME/.config/atuin"
    link config/Thunar "$HOME/.config/Thunar"
    link config/mimeapps.list "$HOME/.config/mimeapps.list"

    log "npm globals (prefix ~/.npm-global)"
    npm config set prefix "$HOME/.npm-global"
    pkglist npm.txt | xargs -r npm install -g

    if [ -n "${GIT_NAME:-}" ]; then
        git config --global user.name "$GIT_NAME"
        git config --global user.email "$GIT_EMAIL"
    fi
}

mod_plugins() {
    [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || die "Run this from a terminal inside Hyprland"

    log "hyprpm plugins"
    hyprpm update
    local name url
    while read -r name url; do
        hyprpm list | grep -q "Repository $name " || hyprpm add "$url" < <(yes) || warn "hyprpm add $url failed"
    done <<'EOF'
hyprland-plugins https://github.com/hyprwm/hyprland-plugins
Hyprspace https://github.com/KZDKM/Hyprspace
dynamic-cursors https://github.com/virtcode/hypr-dynamic-cursors
EOF
    local p
    for p in hyprbars hyprfocus Hyprspace dynamic-cursors; do
        hyprpm enable "$p" || warn "could not enable $p"
    done

    log "Building HyprGlass fork"
    local src=$HOME/.local/src/HyprGlass dest=$HOME/.local/share/hyprglass-macshell
    clone_or_pull "$HYPRGLASS_URL" "$HYPRGLASS_BRANCH" "$src"
    PKG_CONFIG_PATH=/var/cache/hyprpm/$USER/headersRoot/share/pkgconfig make -C "$src" \
        || die "HyprGlass build failed: the fork targets Hyprland 0.56.2, rebase branch $HYPRGLASS_BRANCH onto the pin for your version (hyprpm.toml)"
    mkdir -p "$dest"
    # never overwrite a loaded .so in place
    install -m 755 "$src/hyprglass.so" "$dest/hyprglass.so.new"
    mv "$dest/hyprglass.so.new" "$dest/hyprglass.so"

    hyprpm reload -n
    hyprctl plugin load "$dest/hyprglass.so" || true
    hyprctl reload
}

# --- main -------------------------------------------------------------------

[ "$(id -u)" -ne 0 ] || die "Run as your user, not root (it uses sudo where needed)"
grep -q '^ID=arch' /etc/os-release || die "This is for Arch Linux"
[ "$USER" = azriel ] && [ "$(id -u)" = 1000 ] \
    || warn "Some configs hardcode /home/azriel and /run/user/1000; check hyprland.conf, plugins.conf, hyprlock.conf, macbar/macdock settings.json"

if [ $# -gt 0 ]; then
    selected=("$@")
else
    echo "Modules: ${MODULES[*]}  (plugins runs later, from inside Hyprland)"
    read -r -p "Which to run? [enter = all]: " -a selected
    [ ${#selected[@]} -gt 0 ] || selected=("${MODULES[@]}")
fi
for m in "${selected[@]}"; do
    declare -F "mod_$m" >/dev/null || die "Unknown module: $m"
done

# Ask everything up front so the rest runs unattended
if [[ " ${selected[*]} " == *" dev "* ]] && [ -z "$(git config --global user.name || true)" ]; then
    read -r -p "git user.name: " GIT_NAME
    read -r -p "git user.email: " GIT_EMAIL
fi
if [ $# -eq 0 ]; then
    read -r -p "Run: ${selected[*]}. Continue? [y/N] " ok
    [[ $ok == [yY]* ]] || exit 0
fi

if [[ " ${selected[*]} " != " plugins " ]]; then
    sudo -v
    # keep sudo alive during long AUR builds
    while sleep 60; do sudo -n true; kill -0 $$ 2>/dev/null || exit; done 2>/dev/null &
fi

for m in "${selected[@]}"; do "mod_$m"; done

log "Done"
[ -d "$BACKUP" ] && echo "Old configs moved to $BACKUP"
if [[ " ${selected[*]} " != *" plugins "* ]]; then
    cat <<'EOF'
Next:
  1. Reboot and log into Hyprland from SDDM
  2. In a terminal: ./install.sh plugins   (hyprpm plugins + HyprGlass fork)
  3. gh auth login, then add wallpapers to ~/Pictures/Wallpapers
EOF
fi
