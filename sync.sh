#!/usr/bin/env bash
# Copy this machine's current configs into the repo, check the package lists, then scan
# for secrets. Run on the source machine before committing.
set -euo pipefail

REPO=$(dirname "$(realpath "$0")")
cd "$REPO"

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
# packages/*.txt are curated by hand (essentials only), so they are not regenerated.
# Flag entries that are no longer installed here.
stale=$(grep -hvE '^\s*(#|$)' packages/pacman.txt packages/aur.txt | while read -r p; do
    pacman -Qq "$p" >/dev/null 2>&1 || echo "$p"; done)
[ -z "$stale" ] || echo "!! listed but not installed here: $(echo $stale)"

echo "==> secret scan"
if grep -rInE '(ghp_|gho_|github_pat_|sk-ant-|sk-[A-Za-z0-9]{20}|AKIA[0-9A-Z]{16}|xox[bp]-|-----BEGIN [A-Z ]*PRIVATE KEY|(api[_-]?key|token|secret|password)\s*[=:]\s*\S{8,})' \
        --exclude-dir=.git --exclude=sync.sh . ; then
    echo "!! possible secrets above, review before committing" >&2
    exit 1
fi
echo "clean"
git status --short
