#!/usr/bin/env bash
# end4-pC's region snip (Super+Shift+S) saves "screenshot-*.png" silently. Watch the save folder and
# notify as "Screen Snip" so it matches Print/Ctrl+Print (notification-sound.sh adds the shutter).
# Ctrl+Print's "Screenshot_*.png" is skipped: its keybind already notifies.
# ponytail: folder is read once at startup; changing screenSnip.savePath needs a re-login
dir=$(jq -r '.screenSnip.savePath // empty' "$HOME/.config/illogical-impulse/config.json" 2>/dev/null)
dir=${dir:-$HOME/Pictures/Screenshots}
mkdir -p "$dir"
while true; do  # restart the watcher if gio ever exits
    gio monitor -d "$dir" | while read -r line; do
        [[ $line == *": changes done" ]] || continue
        file=${line#*: }; file=${file%: changes done}
        [[ $(basename "$file") == screenshot-*.png ]] || continue
        notify-send -a "Screen Snip" -i "$file" "Screenshot Saved" "Saved to $file"
    done
    sleep 1
done
