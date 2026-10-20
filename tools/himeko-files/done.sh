#!/usr/bin/env bash
# Dev helper: close the test window, then remove the headless output capture.sh made. In that order: windows on
# a removed output move to your screen, so the output stays if anything is still on its workspace.
set -eu
# Test servers (testdav.py on 127.0.0.1) mounted by the network checks
for m in $(gio mount -l 2>/dev/null | grep -o 'dav://127\.0\.0\.1:[0-9]*/' | sort -u); do gio mount -u "$m" || true; done
hyprctl monitors all -j | jq -e '.[] | select(.name == "HFTEST")' >/dev/null || exit 0
for pid in $(hyprctl clients -j | jq -r '.[] | select(.title|startswith("Files (test) — ")) | .pid'); do kill "$pid"; done
for _ in $(seq 25); do
    hyprctl clients -j | jq -e '.[] | select(.workspace.name == "hftest")' >/dev/null || break
    sleep 0.2
done
if hyprctl clients -j | jq -e '.[] | select(.workspace.name == "hftest")' >/dev/null; then
    echo "windows still on the test workspace; HFTEST kept" >&2; exit 1
fi
hyprctl output remove HFTEST >/dev/null
