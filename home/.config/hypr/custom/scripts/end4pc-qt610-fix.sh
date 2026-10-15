#!/usr/bin/env bash
# Runs at every Hyprland login (custom/execs.lua): re-apply the Ubuntu patches end4-pC's updater drops,
# then make sure the shell is running.
"$(dirname "$0")/end4pc-patches.sh"

# The default exec in hyprland/execs.lua may already have tried (and failed) to start the shell.
# ponytail: fixed 3s wait, fine at login; if this ever races, poll for the qs socket instead
sleep 3
pidof qs >/dev/null || exec qs -c "${qsConfig:-end4-pC}"
