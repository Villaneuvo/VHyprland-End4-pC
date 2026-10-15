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
exit 0
