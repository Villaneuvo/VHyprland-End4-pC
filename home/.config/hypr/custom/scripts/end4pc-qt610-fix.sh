#!/usr/bin/env bash
# end4-pC names a variable `double`, which Qt 6.10's QML parser (Ubuntu 26.04) rejects, so the whole
# shell fails to load. Its updater re-clones the repo and drops our fix; re-apply it on every login.
f="$HOME/.config/quickshell/end4-pC/modules/ii/background/widgets/images/ImageCardWidget.qml"
[ -f "$f" ] && sed -i -E 's/\bvar double\b/var dbl/; s/\) double = (true|false)/) dbl = \1/g; s/if \(double\)/if (dbl)/' "$f"

# The default exec in hyprland/execs.lua may already have tried (and failed) to start the shell.
# ponytail: fixed 3s wait, fine at login; if this ever races, poll for the qs socket instead
sleep 3
pidof qs >/dev/null || exec qs -c "${qsConfig:-end4-pC}"
