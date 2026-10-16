#!/usr/bin/env bash
# Dev helper: memory and idle CPU of the Himeko Files test window (capture.sh's "Files (test)").   perf.sh [SECONDS]
set -eu
pid=$(hyprctl clients -j | jq -r '[.[] | select(.title|startswith("Files (test) — "))][0].pid')
[ "$pid" != null ] || { echo "no Himeko Files test window (start one with capture.sh)" >&2; exit 1; }
t=${1:-10}; hz=$(getconf CLK_TCK)
ticks() { awk '{print $14 + $15}' "/proc/$pid/stat"; }
a=$(ticks); sleep "$t"; b=$(ticks)
rss=$(awk '/VmRSS/{print int($2 / 1024)}' "/proc/$pid/status")
awk -v d=$((b - a)) -v hz="$hz" -v t="$t" -v rss="$rss" 'BEGIN { printf "rss_mb=%d idle_cpu_pct=%.2f\n", rss, 100 * d / hz / t }'
