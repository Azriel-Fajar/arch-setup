#!/usr/bin/env bash
# Copy this machine's current configs and package lists into the repo, then scan
# for secrets. Run on the source machine before committing.
set -euo pipefail

REPO=$(dirname "$(realpath "$0")")
cd "$REPO"

# Installed per machine by install.sh (gpu_packages)
HW_PKGS='^(intel-ucode|amd-ucode|intel-media-driver|libva-intel-driver|vulkan-intel|vulkan-radeon|nvidia.*|lib32-nvidia-utils)$'

echo "==> configs"
mkdir -p config
rsync -a --delete \
    --exclude .git --exclude .superpowers --exclude 'backup-*/' --exclude '*.bak*' --exclude '*.pre-nwg' \
    --exclude colors.conf --exclude monitors.conf --exclude monitors.lua --exclude workspaces.conf \
    --exclude sddm/macos/background.jpg \
    "$HOME/.config/hypr/" config/hypr/
for d in macbar macdock matugen rofi kitty wlogout gtk-3.0 mako environment.d Thunar atuin; do
    rsync -a --delete --exclude '*.bak' "$HOME/.config/$d/" "config/$d/"
done
cp "$HOME/.config/mimeapps.list" "$HOME/.config/starship.toml" config/
mkdir -p home assets/icons
cp "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.zshrc" "$HOME/.blerc" home/
rsync -a --delete "$HOME/.local/share/icons/Bibata-Modern-Classic-Hypr" assets/icons/

echo "==> package lists"
mkdir -p packages
# Shell tools the zsh/kitty configs expect, listed even if not installed here yet
SHELL_PKGS=(zsh zsh-completions zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search
            atuin starship fzf zoxide eza bat fd)
{ pacman -Qqen | grep -vE "$HW_PKGS"; printf '%s\n' "${SHELL_PKGS[@]}"; } | sort -u > packages/pacman.txt
{ pacman -Qqem; echo mactahoe-icon-theme-git; echo fzf-tab; } | sort -u > packages/aur.txt
npm ls -g --depth=0 --parseable 2>/dev/null | tail -n +2 | sed 's|.*/node_modules/||' > packages/npm.txt
flatpak list --app --columns=application 2>/dev/null > packages/flatpak.txt || true
wc -l packages/*.txt

echo "==> secret scan"
if grep -rInE '(ghp_|gho_|github_pat_|sk-ant-|sk-[A-Za-z0-9]{20}|AKIA[0-9A-Z]{16}|xox[bp]-|-----BEGIN [A-Z ]*PRIVATE KEY|(api[_-]?key|token|secret|password)\s*[=:]\s*\S{8,})' \
        --exclude-dir=.git --exclude=sync.sh . ; then
    echo "!! possible secrets above, review before committing" >&2
    exit 1
fi
echo "clean"
git status --short
