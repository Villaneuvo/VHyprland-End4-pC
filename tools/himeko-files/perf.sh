#!/usr/bin/env bash
# Dev helper: memory and idle CPU of the running Himeko Files window.   perf.sh [SECONDS]
set -eu
pid=$(hyprctl clients -j | jq -r '[.[] | select(.title|startswith("Files — "))][0].pid')
[ "$pid" != null ] || { echo "Himeko Files is not running" >&2; exit 1; }
t=${1:-10}; hz=$(getconf CLK_TCK)
ticks() { awk '{print $14 + $15}' "/proc/$pid/stat"; }
a=$(ticks); sleep "$t"; b=$(ticks)
rss=$(awk '/VmRSS/{print int($2 / 1024)}' "/proc/$pid/status")
awk -v d=$((b - a)) -v hz="$hz" -v t="$t" -v rss="$rss" 'BEGIN { printf "rss_mb=%d idle_cpu_pct=%.2f\n", rss, 100 * d / hz / t }'
