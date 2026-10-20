#!/usr/bin/env bash
# Patches end4-pC needs on Ubuntu 26.04. Its updater re-clones the repo and drops them, so
# end4pc-qt610-fix.sh re-runs this at every login; install.sh runs it once after cloning.
# Each sed only matches the original upstream text, so running it again changes nothing.
E4="$HOME/.config/quickshell/end4-pC"

# Qt 6.10's QML parser rejects a variable named `double`, so the whole shell fails to load
f="$E4/modules/ii/background/widgets/images/ImageCardWidget.qml"
[ -f "$f" ] && sed -i -E 's/\bvar double\b/var dbl/; s/\) double = (true|false)/) dbl = \1/g; s/if \(double\)/if (dbl)/' "$f"

# Session menu "Logout" runs `pkill Hyprland`; start-hyprland's watchdog treats that as a crash and
# restarts Hyprland. hyprshutdown is the clean exit Hyprland's docs recommend.
f="$E4/modules/common/functions/Session.qml"
[ -f "$f" ] && sed -i 's#Quickshell.execDetached(\["pkill", "-i", "Hyprland"\]);#Quickshell.execDetached(["bash", "-c", "hyprshutdown -t \x27Logging out...\x27 || hyprctl dispatch \x27hl.dsp.exit()\x27"]);#' "$f"
# Session menu "Sleep": suspend now, hibernate later (falls back to plain suspend where that isn't set up)
[ -f "$f" ] && sed -i 's#"systemctl suspend || loginctl suspend"#"systemctl suspend-then-hibernate || systemctl suspend || loginctl suspend"#' "$f"

# Wallpaper thumbnails: magick can't write into ~/.cache/thumbnails/x-large if the folder doesn't exist yet,
# so the wallpaper pickers showed empty tiles. Create the folder first.
f="$E4/modules/common/widgets/ThumbnailImage.qml"
[ -f "$f" ] && sed -i "s#\[ -f '\${thumbPath}' \] \&\& exit 0 || { tmp=#[ -f '\${thumbPath}' ] \&\& exit 0 || { mkdir -p \"\$(dirname '\${thumbPath}')\"; tmp=#" "$f"

# Notifications: a left click opens the app (like the "Activate" button), and Chrome's
# temp-file logos show the app icon instead of a broken one. Skipped if already applied.
p="$(dirname "$0")/end4pc-notifications.patch"
patch -d "$E4" -p1 --dry-run -R -s -f < "$p" >/dev/null 2>&1 ||
    patch -d "$E4" -p1 -N -s -f --no-backup-if-mismatch -r - < "$p" ||
    echo "end4pc-patches: notifications patch no longer applies (end4-pC changed upstream)" >&2

# Window icons: AppSearch.guessIcon has no cache, and bar/dock bindings re-ask it on every window event; a class
# without a desktop entry (Chrome --app windows) runs a full fuzzy search each time, thousands of times a second,
# which pegged the shell at 100% CPU and made everything lag. Cache per class. Skipped if already applied.
p="$(dirname "$0")/end4pc-iconcache.patch"
patch -d "$E4" -p1 --dry-run -R -s -f < "$p" >/dev/null 2>&1 ||
    patch -d "$E4" -p1 -N -s -f --no-backup-if-mismatch -r - < "$p" ||
    echo "end4pc-patches: icon cache patch no longer applies (end4-pC changed upstream)" >&2
exit 0
