#!/usr/bin/env bash
# Windows+P style display switcher for the laptop screen + one external monitor.
# Usage: display-mode.sh [extend|mirror|external|laptop]
#   (no argument = themed picker in ../display-switcher/shell.qml, fuzzel menu as fallback)
# Changes are runtime-only: `hyprctl reload` or a re-login returns to ii's default (auto extend).
laptop=eDP-1
monitors=$(hyprctl monitors all -j)
ext=$(jq -r --arg l "$laptop" '[.[] | select(.name != $l)][0].name // empty' <<< "$monitors")
if [ -z "$ext" ]; then
    notify-send -a "Display" "No second monitor" "Plug in a monitor, then try again."
    exit 0
fi

mode=$1
if [ -z "$mode" ]; then
    current=$(jq -r --arg l "$laptop" --arg e "$ext" '
        (map({(.name): .}) | add) as $m
        | if $m[$e].disabled then "laptop" elif $m[$l].disabled then "external"
          elif $m[$e].mirrorOf != "none" then "mirror" else "extend" end' <<< "$monitors")
    model=$(jq -r --arg e "$ext" '.[] | select(.name == $e) | .model // empty' <<< "$monitors")
    primary=$(hyprctl getoption cursor:default_monitor | sed -n "s/^str: //p")
    DISPLAY_LAPTOP=$laptop DISPLAY_EXT=$ext DISPLAY_EXT_MODEL=${model:-$ext} DISPLAY_CURRENT=$current DISPLAY_PRIMARY=$primary \
        qs --no-duplicate -p "$HOME/.config/hypr/custom/display-switcher/shell.qml" && exit 0
    choice=$(printf '%s\n' "Extend: use both screens" "Duplicate: same picture on both" \
        "Second screen only: $ext" "PC screen only: laptop screen" |
        fuzzel --dmenu --prompt "Display ($ext): " --lines 4) || exit 0
    case $choice in
        Extend*) mode=extend ;; Duplicate*) mode=mirror ;;
        Second*) mode=external ;; PC*) mode=laptop ;;
    esac
fi

# A runtime hl.monitor() keeps fields from earlier calls, so every call spells out disabled and mirror
mon() { hyprctl eval "hl.monitor({ output = '$1', mode = 'preferred', scale = 1, $2 })" >/dev/null; }
on="disabled = false, mirror = ''"
case $mode in
    # Extend = the configured desk layout (~/.config/hypr/monitors.lua, else ii's auto placement)
    extend)   hyprctl reload >/dev/null ;;
    mirror)   mon "$laptop" "$on, position = '0x0'"; mon "$ext" "disabled = false, position = 'auto', mirror = '$laptop'" ;;
    # Enable the target screen before disabling the other one, so there is always a live output
    external) mon "$ext" "$on, position = '0x0'"; mon "$laptop" "disabled = true, mirror = ''" ;;
    laptop)   mon "$laptop" "$on, position = '0x0'"; mon "$ext" "disabled = true, mirror = ''" ;;
    *) echo "unknown mode: $mode" >&2; exit 1 ;;
esac
notify-send -a "Display" "Display mode: $mode" "Back to default: Super+Alt+P → Extend, or hyprctl reload"
