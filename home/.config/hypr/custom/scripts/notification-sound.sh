#!/usr/bin/env bash
# end4-pC shows notifications silently (GNOME Shell plays a sound itself). Play Ubuntu's notification
# sound for every incoming notification, independent of end4-pC so its updates can't break it.
# Screenshot notifications ("Screen Snip": Super+Shift+S via snip-notify.sh, Print/Ctrl+Print via
# custom/keybinds.lua) get GNOME's shutter sound instead.
# ponytail: ignores end4-pC's Do Not Disturb (it isn't exposed outside the shell); 1s debounce for bursts
message=/usr/share/sounds/Yaru/stereo/message-new-instant.oga
shutter=/usr/share/sounds/freedesktop/stereo/screen-capture.oga
last=0
while true; do  # restart the monitor if dbus-monitor ever exits (e.g. gets killed)
    dbus-monitor --session "type='method_call',interface='org.freedesktop.Notifications',member='Notify'" 2>/dev/null |
    while read -r line; do
        [[ $line == *"member=Notify"* ]] || continue
        read -r app_name   # Notify args: app_name, replaces_id, app_icon, summary, ...
        now=$(date +%s)
        (( now - last >= 1 )) || continue
        last=$now
        if [[ $app_name == 'string "Screen Snip"' ]]; then pw-play "$shutter" &
        else pw-play "$message" &
        fi
    done
    sleep 1
done
