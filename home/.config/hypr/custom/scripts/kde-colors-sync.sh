#!/usr/bin/env bash
# end4-pC writes Material You KDE color schemes (kde-material-you-colors) on every wallpaper/accent change,
# but *applying* one needs plasma-apply-colorscheme, which Ubuntu only ships with Plasma. Without it Qt apps
# (Dolphin, System Settings...) keep whatever colors kdeglobals had on install day. This copies the current
# scheme into kdeglobals and tells running Qt/KDE apps to reload their palette.
# Run by ~/.config/systemd/user/kde-colors-sync.path whenever the scheme files change.
dir=${XDG_DATA_HOME:-$HOME/.local/share}/color-schemes

# A named palette (end4-pC "Color scheme" setting) is written to IllogicalNamed; otherwise the wallpaper one.
if [ "$dir/IllogicalNamed.colors" -nt "$dir/MaterialYouDark.colors" ]; then
    name=IllogicalNamed
elif [ "$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)" = "'prefer-light'" ]; then
    name=MaterialYouLight
else
    name=MaterialYouDark
fi
scheme="$dir/$name.colors"
[ -f "$scheme" ] || exit 0

# Every key of every group, nested groups ("[Colors:Header][Inactive]") as several --group arguments
awk '/^\[/ { g = substr($0, 2, length($0) - 2); gsub(/\]\[/, "\t", g); next }
     /=/ && g != "" { i = index($0, "="); print g "\t" substr($0, 1, i - 1) "\t" substr($0, i + 1) }' "$scheme" |
while IFS= read -r line; do
    IFS=$'\t' read -ra f <<< "$line"
    n=${#f[@]}; key=${f[n-2]}; value=${f[n-1]}
    [ "${f[0]}" = General ] && [ "$key" = Name ] && continue
    args=()
    for ((i = 0; i < n - 2; i++)); do args+=(--group "${f[i]}"); done
    kwriteconfig6 --file kdeglobals "${args[@]}" --key "$key" "$value"
done
kwriteconfig6 --file kdeglobals --group General --key ColorScheme "$name"

# KGlobalSettings::PaletteChanged (0): running KDE apps re-read the palette
dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:0 int32:0
