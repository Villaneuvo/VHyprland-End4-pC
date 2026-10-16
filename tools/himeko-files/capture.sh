#!/usr/bin/env bash
# Dev helper: restart Himeko Files on an invisible headless output (HFTEST, far right of the layout so the cursor
# can't reach it), drive it over IPC, and save a capture of its window. Windows on hidden workspaces get no
# frames, so they can't be captured; a headless output renders without showing anything on your screens.
# Remove the output when done:  hyprctl output remove HFTEST
#   capture.sh OUT.png [FOLDER] [-- "fn arg" ...]      e.g. capture.sh /tmp/a.png ~/Pictures -- "view details"
# Env: WAIT (seconds for the app to start, default 3), SIZE="W H" (float the window at that size),
#      HF_ANIMATE (passed to the app; 0 = animations off).
# The test window is titled "Files (test) — …": only that window is ever closed or captured, never yours.
set -eu
here=$(dirname "$(readlink -f "$0")")
app=${APP_DIR:-$HOME/.config/hypr/custom/himeko-files}   # APP_DIR: run another copy (e.g. an old commit)
out=$1; folder=${2:-$HOME}
mkdir -p "$(dirname "$out")"
shift; [ $# -gt 0 ] && shift
[ "${1:-}" = "--" ] && shift
test_title="Files (test) — "
if ! hyprctl monitors all -j | jq -e '.[] | select(.name == "HFTEST")' >/dev/null; then
    hyprctl eval 'hl.monitor({ output = "HFTEST", mode = "1920x1200@30", position = "20000x0", scale = 1 })' >/dev/null
    # default = true: the output opens on its own named workspace instead of taking a number of yours
    hyprctl eval 'hl.workspace_rule({ workspace = "name:hftest", monitor = "HFTEST", default = true })' >/dev/null
    hyprctl output create headless HFTEST >/dev/null
    sleep 1
fi
for pid in $(hyprctl clients -j | jq -r --arg t "$test_title" '.[] | select(.title|startswith($t)) | .pid'); do kill "$pid"; done
sleep 0.8
# Belt and braces: exec rules can miss the window (it's started through sh -> env -> bash -> qs)
hyprctl eval 'hl.window_rule({match = {title = "^Files \\(test\\)"}, workspace = "name:hftest silent"})' >/dev/null
rules='workspace = "name:hftest silent"'
[ -n "${SIZE:-}" ] && rules="$rules, float = true, size = \"$SIZE\""
hyprctl dispatch "hl.dsp.exec_cmd(\"env HF_TITLE='Files (test)' HF_ANIMATE=${HF_ANIMATE:-} $app/himeko-files '$folder'\", { $rules })" >/dev/null
sleep "${WAIT:-3}"
# IPC must name the test instance: without --pid, qs picks the OLDEST instance, which can be one of yours
pid=$(hyprctl clients -j | jq -r --arg t "$test_title" '[.[] | select(.title|startswith($t))][0].pid')
[ "$pid" != null ] || { echo "test window did not appear" >&2; exit 1; }
for call in "$@"; do
    # shellcheck disable=SC2086 # "fn arg" splits into the IPC function and its argument on purpose
    qs ipc --pid "$pid" call files $call >/dev/null
    sleep 0.4
done
sleep 1
CAP_TITLE="$test_title" CAP_OUT="$out" timeout 12 qs -p "$here/wincap.qml" 2>&1 | grep -q "SAVED true" ||
    { echo "capture failed" >&2; exit 1; }
echo "$out"
