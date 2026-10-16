#!/usr/bin/env bash
# Dev helper: restart Himeko Files on workspace 9 (silently: the visible workspace never changes), drive it
# over IPC, and save a capture of its window.
#   capture.sh OUT.png [FOLDER] [-- "fn arg" ...]      e.g. capture.sh /tmp/a.png ~/Pictures -- "view details"
# Env: WAIT (seconds for the app to start, default 3), SIZE="W H" (float the window at that size),
#      HF_ANIMATE (passed to the app; 0 = animations off).
set -eu
here=$(dirname "$(readlink -f "$0")")
app=$HOME/.config/hypr/custom/himeko-files
out=$1; folder=${2:-$HOME}
mkdir -p "$(dirname "$out")"
shift; [ $# -gt 0 ] && shift
[ "${1:-}" = "--" ] && shift
for pid in $(hyprctl clients -j | jq -r '.[] | select(.title|startswith("Files — ")) | .pid'); do kill "$pid"; done
sleep 0.8
rules='workspace = "9 silent"'
[ -n "${SIZE:-}" ] && rules="$rules, float = true, size = \"$SIZE\""
hyprctl dispatch "hl.dsp.exec_cmd(\"env HF_ANIMATE=${HF_ANIMATE:-} $app/himeko-files '$folder'\", { $rules })" >/dev/null
sleep "${WAIT:-3}"
for call in "$@"; do
    # shellcheck disable=SC2086 # "fn arg" splits into the IPC function and its argument on purpose
    qs -p "$app/shell.qml" ipc call files $call >/dev/null
    sleep 0.4
done
sleep 1
CAP_TITLE="Files — " CAP_OUT="$out" timeout 12 qs -p "$here/wincap.qml" 2>&1 | grep -q "SAVED true" ||
    { echo "capture failed" >&2; exit 1; }
echo "$out"
