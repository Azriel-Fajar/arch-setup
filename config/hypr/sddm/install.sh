#!/usr/bin/env bash
# Install the macOS SDDM theme and make it the current one.
# Usage: sddm/install.sh   (re-runs itself with sudo)
# Rollback: copy /etc/sddm-theme.conf.bak over /etc/sddm.conf.d/theme.conf
set -euo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"

user=${SUDO_USER:?run this from your user account, not a root shell}
home=$(getent passwd "$user" | cut -d: -f6)
src=$(dirname "$(realpath "$0")")/macos
dest=/usr/share/sddm/themes/macos

install -d "$dest/icons"
install -m 644 "$src"/Main.qml "$src"/metadata.desktop "$src"/theme.conf "$dest"/
install -m 644 "$src"/icons/*.svg "$dest/icons"/

# Background follows the desktop wallpaper. The file is owned by the user so
# scripts/wallpaper.sh can refresh it without root.
wall=$(cat "$home/.cache/current-wallpaper" 2>/dev/null || true)
[ -f "$wall" ] || wall=$home/Pictures/Wallpapers/wallpaper.png
install -m 644 -o "$user" -g "$user" "$wall" "$dest/background.jpg"

# Avatar: SDDM can't read ~ (mode 700), so copy ~/.face where it looks
if [ -f "$home/.face" ]; then
    install -m 644 "$home/.face" "/usr/share/sddm/faces/$user.face.icon"
fi

conf=/etc/sddm.conf.d/theme.conf
# SDDM loads every file in sddm.conf.d, so the backup must live outside it
bak=/etc/sddm-theme.conf.bak
[ -e "$conf.bak" ] && mv "$conf.bak" "$bak"
[ -e "$bak" ] || cp "$conf" "$bak"
printf '[Theme]\nCurrent=macos\n' > "$conf"
echo "SDDM theme set to macos (previous config: $bak)"

# /etc/sddm.conf and other conf.d files can override theme.conf; point them at macos too
for f in /etc/sddm.conf /etc/sddm.conf.d/*.conf; do
    [ "$f" != "$conf" ] && [ -f "$f" ] && grep -q '^Current=' "$f" || continue
    b=/etc/sddm-$(basename "$f").bak
    [ -e "$b" ] || cp "$f" "$b"
    sed -i 's/^Current=.*/Current=macos/' "$f"
    echo "Overriding theme in $f also set to macos (previous: $b)"
done
