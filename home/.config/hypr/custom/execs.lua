
-- Started on Hyprland login only, so plain (non-uwsm) Hyprland gets them too; GNOME is unaffected
hl.on("hyprland.start", function ()
    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/end4pc-qt610-fix.sh") -- re-patch end4-pC after its updater, then ensure it runs
    hl.exec_cmd("pidof hyprsunset || hyprsunset") -- night light backend used by end4-pC
    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/notification-sound.sh") -- end4-pC has no notification sound
    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/snip-notify.sh") -- notify for Super+Shift+S snips
    hl.exec_cmd("/usr/libexec/gsd-disk-utility-notify") -- GNOME's SMART disk-health warnings
    hl.exec_cmd("udiskie --automount --notify --no-tray") -- auto-mount USB drives like GNOME did
    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/idle-monitor-shim.py") -- GNOME idle-time API for time-tracking apps
    hl.exec_cmd("systemctl --user start foot-server.socket kde-baloo.service") -- keep these systemd-managed
    hl.exec_cmd("/usr/libexec/evolution-data-server/evolution-alarm-notify") -- calendar reminders
    hl.exec_cmd("sleep 60 && update-notifier") -- Ubuntu updates (same 60s delay GNOME uses)
end)
