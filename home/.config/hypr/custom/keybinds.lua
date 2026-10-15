hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )
hl.bind("SUPER + escape", hl.dsp.global("quickshell:settingsToggle"), {description = "Toggle settings"})

-- Volume keys with GNOME's "tick" feedback sound (same commands/flags as hyprland/keybinds.lua)
local volumeTick = " && pw-play /usr/share/sounds/Yaru/stereo/audio-volume-change.oga"
hl.unbind("XF86AudioRaiseVolume")
hl.unbind("XF86AudioLowerVolume")
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%+ -l 1.5" .. volumeTick),
    { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-" .. volumeTick),
    { locked = true, repeating = true })

-- Full-screen screenshots (same captures as hyprland/keybinds.lua) plus a notification like
-- end4-pC's region snip. Notifying as "Screen Snip" also makes custom/scripts/notification-sound.sh
-- play the shutter sound, so all three screenshot keys behave the same.
local grimMonitor = "grim -o \"$(hyprctl activeworkspace -j | jq -r '.monitor')\""
hl.unbind("Print")
hl.unbind("CTRL + Print")
hl.bind("Print", hl.dsp.exec_cmd(grimMonitor .. " - | wl-copy && " ..
    "notify-send -a 'Screen Snip' -i image-x-generic 'Screenshot Copied' 'Copied to clipboard'"),
    { locked = true, description = "Utilities: Screenshot >> clipboard" })
hl.bind("CTRL + Print", hl.dsp.exec_cmd(
    "f=\"$(xdg-user-dir PICTURES)/Screenshots/Screenshot_$(date '+%Y-%m-%d_%H.%M.%S').png\" && " ..
    "mkdir -p \"$(dirname \"$f\")\" && " .. grimMonitor .. " \"$f\" && wl-copy < \"$f\" && " ..
    "notify-send -a 'Screen Snip' -i \"$f\" 'Screenshot Saved' \"Saved to $f\""),
    { locked = true, description = "Utilities: Screenshot >> clipboard & file" })

-- Sleep: suspend now, hibernate later (enable-hibernate.sh sets the delay); plain suspend where that isn't set up
hl.unbind("SUPER + SHIFT + L")
hl.bind("SUPER + SHIFT + L", hl.dsp.exec_cmd("systemctl suspend-then-hibernate || systemctl suspend || loginctl suspend"),
    { locked = true, description = "Session: Sleep" })

-- Windows+P style display modes (Super+P is ii's "pin window"). Emergency reset re-enables every screen.
hl.bind("SUPER + ALT + P", hl.dsp.exec_cmd("$HOME/.config/hypr/custom/scripts/display-mode.sh"),
    { description = "Display: Choose mode (extend/mirror/single)" })
hl.bind("SUPER + ALT + SHIFT + P", hl.dsp.exec_cmd("hyprctl reload"),
    { locked = true, description = "Display: Reset to default (all screens on)" })
