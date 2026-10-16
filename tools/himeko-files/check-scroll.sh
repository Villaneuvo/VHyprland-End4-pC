#!/usr/bin/env bash
# Dev check: a rebuilt listing (a file appears, the info panel changes the column count) keeps its scroll
# position; another folder starts at the top. Runs on the headless test output (capture.sh); done.sh cleans up.
set -eu
here=$(dirname "$(readlink -f "$0")")
dir=$(mktemp -d); shots=$(mktemp -d); trap 'rm -rf "$dir" "$shots"' EXIT
mkdir "$dir/sub"
for i in $(seq 1 400); do : > "$dir/file $i.txt"; : > "$dir/sub/file $i.txt"; done
fails=0
expect() {
    got=$(qs ipc --pid "$pid" call files scrollY)
    if [ "$got" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1: got $got, want $2"; fails=$((fails + 1)); fi
}
for view in icons details; do
    "$here/capture.sh" "$shots/$view.png" "$dir" -- "view $view" "scroll 800" >/dev/null
    pid=$(hyprctl clients -j | jq -r '[.[] | select(.title|startswith("Files (test) — "))][0].pid')
    expect "$view: scrolled" 800
    : > "$dir/new $view.txt"; sleep 1
    expect "$view: file added" 800
    qs ipc --pid "$pid" call files info true; sleep 1.2
    expect "$view: info panel" 800
    qs ipc --pid "$pid" call files go "$dir/sub"; sleep 1.5
    expect "$view: other folder" 0
done
echo "check-scroll: $fails failures"
