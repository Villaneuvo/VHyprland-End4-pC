# Himeko Files Polish & Motion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expressive end4-pC-style motion, a scroll edge effect, narrow-window layouts, folder item counts and
Nautilus-style dates in Himeko Files, without raising its CPU or memory use.

**Architecture:** Motion tokens (end4-pC's bezier curves) live in the `Theme` singleton and an `Anim` helper;
each component animates only `opacity`, `scale` and translate offsets through small `Behavior`s/animations.
Pure logic (dates, count tally) lives in the `Fs` singleton and is checked by a `qs -p selftest.qml` script.
Visual results are checked through the app's IPC and an offscreen window capture on workspace 9.

**Tech Stack:** Quickshell 0.3.2 (QML, Qt 6.10), bash, `find`, `hyprctl`, ImageMagick (`magick`) for
inspecting captures.

**Spec:** `docs/superpowers/specs/2026-10-16-himeko-files-polish-motion-design.md`

## Global Constraints

- Edit the live app in `~/.config/hypr/custom/himeko-files/`; `./sync.sh` (repo root) copies it into
  `home/`. Never edit `home/.config/hypr/custom/himeko-files/` directly.
- Commit messages carry **no** AI attribution or `Co-Authored-By` lines.
- Never open a test window on the user's visible workspace: launch only through
  `tools/himeko-files/capture.sh` (workspace 9, silent). Kill test instances by window PID, never
  `pkill -f` (the pattern matches your own shell).
- Animate only `opacity`, `scale` and `Translate` offsets. Never animate `width`/`height`/`implicit*` or
  anything inside a layout.
- Every duration goes through `Theme.dur(kind)` (or `Anim`), so animations-off means 0 ms everywhere.
- Motion tokens, exact values: fastSpatial `[0.42, 1.67, 0.21, 0.90, 1, 1]` 350 ms; spatial
  `[0.38, 1.21, 0.22, 1.00, 1, 1]` 500 ms; effects `[0.34, 0.80, 0.34, 1.00, 1, 1]` 200 ms; enter
  `[0.05, 0.7, 0.1, 1, 1, 1]` 400 ms.
- Theme color names never start with `on` + capital (QML reads `onX` as a signal handler): use `text`,
  `textDim`, `ink*`.
- `ListView` pins delegates at x = 0: horizontal padding goes inside delegates (`root.pad`).
- No new packages.
- Idle CPU stays 0 % (< 0.5 % over 10 s); RSS not higher than the Task 1 baseline.

## Review Focus

- **Navigating fast** (open a folder, Back immediately): content must end at opacity 1 and offset 0, never
  stuck half-faded. Pinned in Task 5, Step 6.
- **Counts arriving late**: a count for folder A must not be applied after the user moved to folder B.
  Pinned in Task 3, Step 7.
- **Animations turned off** system-wide: tiles must not stay at opacity 0 (the appear animation sets
  opacity 0 first). Pinned in Task 5, Step 7 (`HF_ANIMATE=0`).
- **Narrow window on a deep path with long names**: nothing overlaps in the toolbar, header or tabs.
  Pinned in Task 8, Step 5.
- **Menu opened near the window edge**: the clamped menu still pops from inside itself (origin within
  bounds). Pinned in Task 6, Step 8.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `tools/himeko-files/wincap.qml` | Capture one toplevel to PNG offscreen (dev only, not installed) | Create |
| `tools/himeko-files/capture.sh` | Restart the app on workspace 9, drive it over IPC, capture it | Create |
| `tools/himeko-files/perf.sh` | RSS and idle CPU of the running app | Create |
| `~/.config/hypr/custom/himeko-files/selftest.qml` | Logic self-check (dates, counts, motion tokens) | Create |
| `…/Anim.qml` | `NumberAnimation` bound to a motion token | Create |
| `…/Theme.qml` | Motion tokens, `animate`, `dur()` | Modify |
| `…/Fs.qml` | `date(d, now)`, `tallyCounts()`, `countSubfolders()`, `countLabel()` | Modify |
| `…/Tab.qml` | Navigation direction, load time, folder counts | Modify |
| `…/ItemTile.qml` | Appear, hover, selection pop, item counts | Modify |
| `…/DetailsList.qml` | Item counts in Size, selection pop, row appear | Modify |
| `…/IconGrid.qml` | Appear order, debounced columns | Modify |
| `…/Sidebar.qml` | Gliding highlight pill | Modify |
| `…/Menu.qml` | Pop from pointer, submenu slide | Modify |
| `…/Glass.qml` | Animated tint | Modify |
| `…/Browser.qml` | Navigation/view transitions, search crossfade, toast, info panel, tabs, scroll edge, narrow layouts | Modify |
| `…/Thumb.qml` | Decode size buckets | Modify |
| `README.md` | One line on motion | Modify |

---

### Task 1: Dev tooling and baseline numbers

**Files:**
- Create: `tools/himeko-files/wincap.qml`
- Create: `tools/himeko-files/capture.sh`
- Create: `tools/himeko-files/perf.sh`

**Interfaces:**
- Produces: `tools/himeko-files/capture.sh OUT.png [FOLDER] [-- "ipc-fn arg" ...]` (env: `WAIT` seconds
  to start, default 3; `SIZE="W H"` makes the window float at that size; `HF_ANIMATE` passed through);
  `tools/himeko-files/perf.sh [SECONDS]` printing `rss_mb=N idle_cpu_pct=N.NN`.

- [ ] **Step 1: Create the window capture helper**

`tools/himeko-files/wincap.qml`:

```qml
// Dev helper: saves one window to a PNG without showing anything (a 1x1 transparent background layer hosts
// the capture). Env: CAP_TITLE (title prefix), CAP_OUT (png path).
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    id: root
    property string title: Quickshell.env("CAP_TITLE")
    property string out: Quickshell.env("CAP_OUT")
    readonly property var target: ToplevelManager.toplevels.values.find(t => t.title.startsWith(root.title)) ?? null
    PanelWindow {
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "wincap"
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: 1
        implicitHeight: 1
        color: "transparent"
        anchors { top: true; left: true }
        ScreencopyView {
            id: view
            width: 2000; height: 1300
            live: true
            captureSource: root.target
            onHasContentChanged: if (hasContent) shot.start()
        }
        Timer {
            id: shot; interval: 600
            onTriggered: view.grabToImage(r => { console.log("SAVED", r.saveToFile(root.out)); Qt.quit() },
                                          Qt.size(view.sourceSize.width, view.sourceSize.height))
        }
        Timer { interval: 8000; running: true; onTriggered: { console.log("TIMEOUT"); Qt.quit() } }
    }
}
```

- [ ] **Step 2: Create the capture script**

`tools/himeko-files/capture.sh`:

```bash
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
CAP_TITLE="Files — " CAP_OUT="$out" timeout 12 qs -p "$here/wincap.qml" 2>&1 | grep -q SAVED ||
    { echo "capture failed" >&2; exit 1; }
echo "$out"
```

- [ ] **Step 3: Create the perf script**

`tools/himeko-files/perf.sh`:

```bash
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
```

- [ ] **Step 4: Check the tools work**

Run:
```bash
cd ~/VHyprland-End4-pC && chmod +x tools/himeko-files/*.sh
tools/himeko-files/capture.sh /tmp/claude-1000/hf-base.png ~/Pictures/Wallpapers && magick identify /tmp/claude-1000/hf-base.png
hyprctl activeworkspace -j | jq .id
```
Expected: `/tmp/claude-1000/hf-base.png PNG 1892x1127 …` (size may differ by monitor), and the active workspace
is still the one you were on (not 9).

- [ ] **Step 5: Record the baseline**

Run:
```bash
cd ~/VHyprland-End4-pC
tools/himeko-files/capture.sh /tmp/claude-1000/hf-a.png ~/Pictures/Wallpapers >/dev/null; sleep 5; tools/himeko-files/perf.sh 10
tools/himeko-files/capture.sh /tmp/claude-1000/hf-b.png /usr/lib/x86_64-linux-gnu >/dev/null; sleep 5; tools/himeko-files/perf.sh 10
```
Expected: two lines like `rss_mb=… idle_cpu_pct=0.0…`. Write both lines down: they go into this task's
commit message and are the limits Task 9 checks against.

- [ ] **Step 6: Commit**

```bash
cd ~/VHyprland-End4-pC && git add tools/himeko-files
git commit -m "Himeko Files dev tools: offscreen capture, IPC-driven checks, perf numbers

Baseline (before polish & motion):
  Wallpapers: <paste perf.sh line>
  3915-file folder: <paste perf.sh line>"
git push
```

---

### Task 2: Self-check harness and Nautilus-style dates

**Files:**
- Create: `~/.config/hypr/custom/himeko-files/selftest.qml`
- Modify: `~/.config/hypr/custom/himeko-files/Fs.qml` (`function date`)

**Interfaces:**
- Produces: `Fs.date(d: Date, now?: Date): string`; `selftest.qml` with `check(name, got, want)` that later
  tasks append to. Run: `qs -p ~/.config/hypr/custom/himeko-files/selftest.qml 2>&1 | grep -E "^.*(ok  |FAIL)"`.

- [ ] **Step 1: Write the failing test**

`~/.config/hypr/custom/himeko-files/selftest.qml`:

```qml
// Logic self-check. Run: qs -p ~/.config/hypr/custom/himeko-files/selftest.qml
// Prints "ok   name" or "FAIL name: got …, want …", then "selftest: N failures".
import QtQuick
import Quickshell

ShellRoot {
    id: t
    property int failures: 0
    function check(name, got, want) {
        const ok = JSON.stringify(got) === JSON.stringify(want);
        console.log((ok ? "ok   " : "FAIL ") + name + (ok ? "" : ": got " + JSON.stringify(got) + ", want " + JSON.stringify(want)));
        if (!ok) failures++;
    }
    Component.onCompleted: {
        // ---- dates (Fs.date) ----
        const now = new Date(2026, 9, 16, 12, 0, 0);
        const at = (y, mo, d, h, mi) => new Date(y, mo - 1, d, h, mi);
        check("date: seconds ago", Fs.date(new Date(now.getTime() - 30000), now), "Just now");
        check("date: minutes ago", Fs.date(new Date(now.getTime() - 5 * 60000), now), "5 min ago");
        check("date: 59 minutes ago", Fs.date(new Date(now.getTime() - 59 * 60000), now), "59 min ago");
        check("date: earlier today", Fs.date(at(2026, 10, 16, 8, 5), now), "Today, 08:05");
        check("date: yesterday", Fs.date(at(2026, 10, 15, 16, 28), now), "Yesterday, 16:28");
        check("date: 3 days ago", Fs.date(at(2026, 10, 13, 10, 0), now), "3 days ago");
        check("date: 6 days ago", Fs.date(at(2026, 10, 10, 23, 59), now), "6 days ago");
        check("date: this year", Fs.date(at(2026, 10, 9, 10, 0), now), "9 Oct");
        check("date: last year", Fs.date(at(2025, 12, 31, 10, 0), now), "31 Dec 2025");
        check("date: future", Fs.date(at(2026, 10, 17, 9, 0), now), "17 Oct");

        console.log("selftest: " + failures + " failures");
        Qt.quit();
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `qs -p ~/.config/hypr/custom/himeko-files/selftest.qml 2>&1 | grep -E "ok  |FAIL|selftest:"`
Expected: FAIL lines for "seconds ago", "minutes ago", "59 minutes ago", "3 days ago", "6 days ago"
(the current `date()` has none of those buckets), ending with `selftest: 5 failures`.

- [ ] **Step 3: Implement**

In `Fs.qml`, replace the whole `function date(d) { … }` block with:

```qml
    // Nautilus-style: "Just now", "5 min ago", "Today, 14:39", "Yesterday, 16:28", "3 days ago",
    // "12 Oct", "12 Oct 2025". `now` is for the self-check.
    function date(d, now) {
        now = now ?? new Date();
        const t = d.getTime(), diff = now.getTime() - t, min = 60000, day = 86400000;
        const absolute = () => Qt.formatDate(d, d.getFullYear() === now.getFullYear() ? "d MMM" : "d MMM yyyy");
        if (diff < 0) return absolute();
        if (diff < min) return "Just now";
        if (diff < 60 * min) return Math.floor(diff / min) + " min ago";
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
        const thatDay = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
        const days = Math.round((today - thatDay) / day);   // calendar days, safe across DST
        const hm = Qt.formatTime(d, "hh:mm");
        if (days === 0) return "Today, " + hm;
        if (days === 1) return "Yesterday, " + hm;
        if (days < 7) return days + " days ago";
        return absolute();
    }
```

- [ ] **Step 4: Run it to see it pass**

Run: `qs -p ~/.config/hypr/custom/himeko-files/selftest.qml 2>&1 | grep -E "ok  |FAIL|selftest:"`
Expected: ten `ok` lines and `selftest: 0 failures`.

- [ ] **Step 5: Commit**

```bash
cd ~/VHyprland-End4-pC && ./sync.sh >/dev/null && git add -A
git commit -m "Himeko Files: Nautilus-style dates and a logic self-check" && git push
```

(`sync.sh` copies `selftest.qml` because the whole `himeko-files` folder is in `manifest.txt`.)

---

### Task 3: Folder item counts

**Files:**
- Modify: `~/.config/hypr/custom/himeko-files/Fs.qml`
- Modify: `~/.config/hypr/custom/himeko-files/Tab.qml`
- Modify: `~/.config/hypr/custom/himeko-files/ItemTile.qml`
- Modify: `~/.config/hypr/custom/himeko-files/DetailsList.qml`
- Test: `~/.config/hypr/custom/himeko-files/selftest.qml`

**Interfaces:**
- Consumes: `Fs.run(cmd, cb(text, code, err))`, `Fs.lines(text)` (existing).
- Produces: `Fs.tallyCounts(text: string): object` (path → count); `Fs.countSubfolders(dir, cb(counts | null))`;
  `Fs.countLabel(n: number | undefined): string`; `Tab.counts: object | null`; `Tab.countOf(path): number | undefined`.

- [ ] **Step 1: Write the failing tests**

In `selftest.qml`, before the `console.log("selftest: …")` line, add:

```qml
        // ---- item counts (Fs.tallyCounts, Fs.countLabel) ----
        check("tally: counts per parent", Fs.tallyCounts("/a/x\n/a/x\n/a/y\n"), { "/a/x": 2, "/a/y": 1 });
        check("tally: empty output", Fs.tallyCounts(""), {});
        check("tally: names with spaces", Fs.tallyCounts("/a/My Folder\n"), { "/a/My Folder": 1 });
        check("label: unknown", Fs.countLabel(undefined), "Folder");
        check("label: empty", Fs.countLabel(0), "Empty");
        check("label: one", Fs.countLabel(1), "1 item");
        check("label: many", Fs.countLabel(24), "24 items");
```

- [ ] **Step 2: Run them to see them fail**

Run: `qs -p ~/.config/hypr/custom/himeko-files/selftest.qml 2>&1 | grep -E "FAIL|selftest:"`
Expected: errors/FAIL for every new check (`tallyCounts is not a function`), not `0 failures`.

- [ ] **Step 3: Implement the counting in Fs**

In `Fs.qml`, after the `function date(…) {…}` block, add:

```qml
    // ---- folder item counts: one `find` per folder visit counts every subfolder at once ----
    function tallyCounts(text) {
        const counts = {};
        for (const l of lines(text)) counts[l] = (counts[l] ?? 0) + 1;
        return counts;
    }
    // cb(counts) with { subfolderPath: visibleItemCount }; subfolders it doesn't list are empty.
    // cb(null) when it ran out of time (huge trees): callers keep showing "Folder".
    function countSubfolders(dir, cb) {
        run(["timeout", "3", "find", dir, "-mindepth", "2", "-maxdepth", "2", "-not", "-name", ".*", "-printf", "%h\\n"],
            (text, code) => cb(code === 124 ? null : tallyCounts(text)));
    }
    function countLabel(n) {
        if (n === undefined) return "Folder";
        if (n === 0) return "Empty";
        return n === 1 ? "1 item" : n + " items";
    }
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `qs -p ~/.config/hypr/custom/himeko-files/selftest.qml 2>&1 | grep -E "FAIL|selftest:"`
Expected: only `selftest: 0 failures`.

- [ ] **Step 5: Keep the counts per tab**

In `Tab.qml`:

1. After `property string anchor: ""`, add:

```qml
    property var counts: null              // subfolder path -> item count; null until counted
    property string countedPath: ""
    function countOf(p) { return counts ? (counts[p] ?? 0) : undefined; }
```

2. In `function reload()`, after the line `all = list;`, add:

```qml
        // Count the subfolders once per visit (F5 resets countedPath); ignore answers for a folder we left
        if (countedPath !== path && list.some(it => it.isDir)) {
            const asked = path;
            countedPath = path;
            Fs.countSubfolders(asked, (c) => { if (tab.path === asked) tab.counts = c; });
        }
```

3. In `function go(p, record) { … }`, after `all = [];`, add: `counts = null; countedPath = "";`

4. In `Browser.qml`, the F5 handler line `else if (k === Qt.Key_F5) tab.reload();` becomes:

```qml
        else if (k === Qt.Key_F5) { tab.countedPath = ""; tab.counts = null; tab.reload(); }
```

- [ ] **Step 6: Show the counts**

In `ItemTile.qml`, in the wide (folder) column, replace
`Text { text: "Folder"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }` with:

```qml
            Text { text: Fs.countLabel(root.tab.countOf(root.item.path)); color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
```

In `DetailsList.qml`, in the delegate's `Repeater { model: [ … ] }`, replace the first entry
`row.modelData.isDir ? "—" : Fs.size(row.modelData.size),` with:

```qml
                    row.modelData.isDir ? Fs.countLabel(root.tab.countOf(row.modelData.path)) : Fs.size(row.modelData.size),
```

- [ ] **Step 7: Check it, including a count arriving after leaving the folder**

Run:
```bash
cd ~/VHyprland-End4-pC
tools/himeko-files/capture.sh /tmp/claude-1000/hf-counts.png ~ && magick /tmp/claude-1000/hf-counts.png -crop 1892x420+0+150 -resize 1280x /tmp/claude-1000/hf-counts-top.png
tools/himeko-files/capture.sh /tmp/claude-1000/hf-late.png /usr -- "go /usr/share" "go /tmp" && magick /tmp/claude-1000/hf-late.png -resize 1280x /tmp/claude-1000/hf-late-small.png
```
Expected: in `hf-counts-top.png` the folder tiles read "N items" / "Empty" instead of "Folder". In
`hf-late-small.png` (we left `/usr/share` while it was still counting) the `/tmp` folder tiles show their own
counts or "Folder", never counts that belong to `/usr/share` folders. View both images.

- [ ] **Step 8: Commit**

```bash
cd ~/VHyprland-End4-pC && ./sync.sh >/dev/null && git add -A
git commit -m "Himeko Files: item counts on folders (one find per visit, cached)" && git push
```

---

### Task 4: Motion tokens

**Files:**
- Create: `~/.config/hypr/custom/himeko-files/Anim.qml`
- Modify: `~/.config/hypr/custom/himeko-files/Theme.qml`
- Test: `~/.config/hypr/custom/himeko-files/selftest.qml`

**Interfaces:**
- Produces: `Theme.curve: { fastSpatial, spatial, effects, enter }` (6-number bezier arrays);
  `Theme.duration: { fastSpatial: 350, spatial: 500, effects: 200, enter: 400 }`; `Theme.animate: bool`;
  `Theme.dur(kind: string): int`; `Anim { kind: "effects" }` (a `NumberAnimation`).

- [ ] **Step 1: Write the failing test**

In `selftest.qml`, before `console.log("selftest: …")`, add:

```qml
        // ---- motion tokens (Theme) ----
        check("curve: fastSpatial", Theme.curve.fastSpatial, [0.42, 1.67, 0.21, 0.90, 1, 1]);
        check("curve: enter", Theme.curve.enter, [0.05, 0.7, 0.1, 1, 1, 1]);
        const was = Theme.animate;
        Theme.animate = true;
        check("dur: effects", Theme.dur("effects"), 200);
        check("dur: spatial", Theme.dur("spatial"), 500);
        Theme.animate = false;
        check("dur: off", Theme.dur("fastSpatial"), 0);
        Theme.animate = was;
```

- [ ] **Step 2: Run it to see it fail**

Run: `qs -p ~/.config/hypr/custom/himeko-files/selftest.qml 2>&1 | grep -E "FAIL|selftest:"`
Expected: FAIL/errors for the five motion checks.

- [ ] **Step 3: Implement the tokens**

In `Theme.qml`, before the closing `}` of the `Singleton`, add:

```qml
    // ---- motion: end4-pC's curves (Appearance.qml), so the app moves like the shell ----
    readonly property var curve: ({
        fastSpatial: [0.42, 1.67, 0.21, 0.90, 1, 1],   // overshoot, for things that pop
        spatial: [0.38, 1.21, 0.22, 1.00, 1, 1],
        effects: [0.34, 0.80, 0.34, 1.00, 1, 1],       // fades and color
        enter: [0.05, 0.7, 0.1, 1, 1, 1]
    })
    readonly property var duration: ({ fastSpatial: 350, spatial: 500, effects: 200, enter: 400 })
    // Off when GNOME's "enable-animations" or Hyprland's animations are off; HF_ANIMATE=0 forces it (tests)
    property bool animate: Quickshell.env("HF_ANIMATE") !== "0"
    function dur(kind) { return animate ? duration[kind] : 0; }
    Process {
        running: Quickshell.env("HF_ANIMATE") !== "0"
        command: ["bash", "-c", "gsettings get org.gnome.desktop.interface enable-animations; hyprctl getoption animations:enabled -j | jq .int"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                root.animate = l[0] !== "false" && l[1] !== "0";
            }
        }
    }
```

`Theme.qml` already imports `Quickshell.Io` (for `FileView`), which provides `Process`/`StdioCollector`.

`~/.config/hypr/custom/himeko-files/Anim.qml`:

```qml
import QtQuick

// A NumberAnimation on one of the motion tokens:  Behavior on scale { Anim { kind: "fastSpatial" } }
NumberAnimation {
    property string kind: "effects"
    duration: Theme.dur(kind)
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Theme.curve[kind]
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `qs -p ~/.config/hypr/custom/himeko-files/selftest.qml 2>&1 | grep -E "FAIL|selftest:"`
Expected: `selftest: 0 failures`.

- [ ] **Step 5: Commit**

```bash
cd ~/VHyprland-End4-pC && ./sync.sh >/dev/null && git add -A
git commit -m "Himeko Files: motion tokens from end4-pC; animations follow the system switch" && git push
```

---

### Task 5: Content motion (navigation, view switch, tiles, selection, hover)

**Files:**
- Modify: `~/.config/hypr/custom/himeko-files/Tab.qml`
- Modify: `~/.config/hypr/custom/himeko-files/Browser.qml`
- Modify: `~/.config/hypr/custom/himeko-files/IconGrid.qml`
- Modify: `~/.config/hypr/custom/himeko-files/ItemTile.qml`
- Modify: `~/.config/hypr/custom/himeko-files/DetailsList.qml`

**Interfaces:**
- Consumes: `Anim`, `Theme.dur()`, `Theme.animate` (Task 4).
- Produces: `Tab.direction: int` (1 into/forward, -1 back/up, 0 tab switch); `Tab.loadedAt: real`
  (ms timestamp of the first listing of the current folder); `ItemTile.appearOrder: int`.

- [ ] **Step 1: Record the navigation direction and load time in Tab**

In `Tab.qml`:

1. After `property string countedPath: ""` add:

```qml
    property int direction: 1              // 1 = into/forward, -1 = back/up: which way the content slides
    property real loadedAt: 0              // when the current folder was first listed (tiles animate in after it)
    property string loadedPath: ""
```

2. Replace `function go(p, record) {` with `function go(p, record, dir) {`, and right after its first line
   `if (!p || p === path) return;` add: `direction = dir ?? 1;`
3. Replace the three navigation helpers with:

```qml
    function goBack() { if (back.length) { forward = [path].concat(forward); const p = back[back.length - 1]; back = back.slice(0, -1); go(p, false, -1); } }
    function goForward() { if (forward.length) { back = back.concat([path]); const p = forward[0]; forward = forward.slice(1); go(p, false, 1); } }
    function goUp() { if (path !== "/") go(path.slice(0, path.lastIndexOf("/")) || "/", true, -1); }
```

4. In `function reload()`, right after `all = list;`, add:

```qml
        if (loadedPath !== path) { loadedPath = path; loadedAt = Date.now(); }
```

- [ ] **Step 2: Slide and fade the content on navigation; crossfade the views**

In `Browser.qml`:

1. On the `Item { id: view … }` add a translate transform (inside the item, after `Keys.forwardTo: [root]`):

```qml
                transform: Translate { id: viewShift }
```

2. After that `Item { id: view … }` block closes, add:

```qml
            // Opening a folder: the content fades in while sliding 12 px from the side it came from
            ParallelAnimation {
                id: navAnim
                property int dir: 1
                Anim { target: viewShift; property: "x"; from: 12 * navAnim.dir; to: 0; kind: "effects"; duration: Theme.animate ? 250 : 0 }
                Anim { target: view; property: "opacity"; from: 0; to: 1; kind: "effects"; duration: Theme.animate ? 250 : 0 }
            }
```

3. In the existing `Connections { target: root.tab; function onPathChanged() { … } }`, append to the body:
   `navAnim.dir = root.tab.direction; navAnim.restart();`
4. Add next to it:

```qml
    onTabIndexChanged: { navAnim.dir = 0; navAnim.restart(); }
```

5. In `IconGrid { id: iconView … }` replace `visible: root.tab && root.tab.viewMode === "icons"` with:

```qml
                    opacity: root.tab && root.tab.viewMode === "icons" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { Anim { kind: "effects" } }
```

   and in `DetailsList { id: detailsView … }` replace `visible: root.tab && root.tab.viewMode === "details"` with:

```qml
                    opacity: root.tab && root.tab.viewMode === "details" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { Anim { kind: "effects" } }
```

- [ ] **Step 3: Tiles appear in order; hover and selection animate**

In `IconGrid.qml`, in the row delegate (`delegate: Item { id: row …`), add `required property int index` next
to `required property var modelData`, and in the inner tile delegate (`delegate: ItemTile { … }`) add
`required property int index` and the property line:

```qml
                    appearOrder: row.index * grid.columns + index
```

In `ItemTile.qml`:

1. Add properties after `property bool renaming: false`:

```qml
    property int appearOrder: -1          // position among the first tiles of a freshly opened folder
    property real fade: 1
```

2. Replace `opacity: cut ? 0.5 : 1` with:

```qml
    opacity: (cut ? 0.5 : 1) * fade
    scale: containsMouse ? 1.02 : 1
    Behavior on scale { Anim { kind: "effects" } }
    transform: Translate { id: lift }
    // The first 24 tiles of a folder that just opened fade in and rise 8 px, 15 ms apart
    Component.onCompleted: {
        if (!Theme.animate || appearOrder < 0 || appearOrder >= 24 || Date.now() - tab.loadedAt > 600) return;
        fade = 0; lift.y = 8;
        appear.start();
    }
    SequentialAnimation {
        id: appear
        PauseAnimation { duration: root.appearOrder * 15 }
        ParallelAnimation {
            Anim { target: root; property: "fade"; to: 1; kind: "enter" }
            Anim { target: lift; property: "y"; to: 0; kind: "enter" }
        }
    }
```

3. Selection ring: in the square (file) column, in the ring `Rectangle { … border.width: root.selected ? 3 : 0 … }`,
   replace `border.width: root.selected ? 3 : 0` with:

```qml
                border.width: 3
                opacity: root.selected ? 1 : 0
                Behavior on opacity { Anim { kind: "effects" } }
```

4. Cookie check: replace the badge item's `visible: root.selected` with:

```qml
                scale: root.selected ? 1 : 0
                visible: scale > 0
                Behavior on scale { Anim { kind: "fastSpatial" } }
```

In `DetailsList.qml`, the row's cookie check item: replace `visible: row.selected` with:

```qml
                    scale: row.selected ? 1 : 0
                    visible: scale > 0
                    Behavior on scale { Anim { kind: "fastSpatial" } }
```

- [ ] **Step 4: Rows in the details view appear in order too**

In `DetailsList.qml`, in the row delegate (`delegate: MouseArea { id: row …`), add `required property int index`,
`property real fade: 1`, change `opacity: cut ? 0.5 : 1` to `opacity: (cut ? 0.5 : 1) * fade`, and add:

```qml
        transform: Translate { id: rowLift }
        Component.onCompleted: {
            if (!Theme.animate || index >= 24 || Date.now() - root.tab.loadedAt > 600) return;
            fade = 0; rowLift.y = 8;
            rowAppear.start();
        }
        SequentialAnimation {
            id: rowAppear
            PauseAnimation { duration: row.index * 15 }
            ParallelAnimation {
                Anim { target: row; property: "fade"; to: 1; kind: "enter" }
                Anim { target: rowLift; property: "y"; to: 0; kind: "enter" }
            }
        }
```

- [ ] **Step 5: Check the shell still loads and the selftest still passes**

Run:
```bash
qs -p ~/.config/hypr/custom/himeko-files/selftest.qml 2>&1 | grep -E "FAIL|selftest:"
cd ~/VHyprland-End4-pC && tools/himeko-files/capture.sh /tmp/claude-1000/hf-motion.png ~/Pictures/Wallpapers -- "select himeko_nova.jpg" && magick /tmp/claude-1000/hf-motion.png -resize 1280x /tmp/claude-1000/hf-motion-small.png
```
Expected: `selftest: 0 failures`; the capture (taken 1 s after the last call) shows the tiles fully opaque,
in place, the selected tile with its ring and cookie check. View the image.

- [ ] **Step 6: Fast navigation never leaves content half-faded**

Run:
```bash
cd ~/VHyprland-End4-pC && tools/himeko-files/capture.sh /tmp/claude-1000/hf-fast.png ~ -- "go ~/Pictures" "go ~" "go ~/Pictures/Wallpapers"
```
Expected: the image shows the Wallpapers folder fully drawn (not faded, not offset). View the image.

- [ ] **Step 7: Animations off: nothing stays invisible**

Run:
```bash
cd ~/VHyprland-End4-pC && HF_ANIMATE=0 tools/himeko-files/capture.sh /tmp/claude-1000/hf-noanim.png ~/Pictures/Wallpapers -- "select himeko_nova.jpg"
```
Expected: tiles fully visible, ring and check shown. View the image.

- [ ] **Step 8: Commit**

```bash
cd ~/VHyprland-End4-pC && ./sync.sh >/dev/null && git add -A
git commit -m "Himeko Files: content motion (folder slide, view crossfade, tiles appear, selection pop, hover)" && git push
```

---

### Task 6: Chrome motion (sidebar pill, search, menus, toast, info panel, tabs)

**Files:**
- Modify: `~/.config/hypr/custom/himeko-files/Sidebar.qml`
- Modify: `~/.config/hypr/custom/himeko-files/Glass.qml`
- Modify: `~/.config/hypr/custom/himeko-files/Menu.qml`
- Modify: `~/.config/hypr/custom/himeko-files/Browser.qml`

**Interfaces:**
- Consumes: `Anim`, `Theme.dur()` (Task 4).
- Produces: `Menu.origin: point` (pop-out point in the menu's own coordinates).

- [ ] **Step 1: One gliding highlight pill in the sidebar**

In `Sidebar.qml`:

1. Add `property Item activeRow: null` after `signal openDolphin(string path)`.
2. Wrap the `ColumnLayout { id: col … }` in an `Item` that also holds the highlight. Replace the line
   `        ColumnLayout {` (the one with `id: col` below it) with:

```qml
        Item {
            width: parent.width
            implicitHeight: col.implicitHeight
            // The active place's pill: one rectangle that glides between rows instead of each row drawing its own
            Rectangle {
                visible: root.activeRow !== null && root.activeRow.visible
                x: (root.activeRow ? root.activeRow.x : 0) + (root.rail ? 4 : 0)
                y: root.activeRow ? root.activeRow.y : 0
                width: (root.activeRow ? root.activeRow.width : 0) - (root.rail ? 8 : 0)
                height: root.activeRow ? root.activeRow.height : 0
                radius: height / 2
                color: Theme.primaryContainer
                Behavior on y { Anim { kind: "fastSpatial" } }
            }
        ColumnLayout {
```

   and close the new `Item` right after the `ColumnLayout`'s closing brace (add one `}`), keeping
   `contentHeight: col.implicitHeight` on the `Flickable`.
3. In `component PlaceRow`, change the background rectangle's color to stop drawing the active state:
   `color: row.active ? Theme.primaryContainer : (row.containsMouse ? Theme.hover : "transparent")` becomes
   `color: !row.active && row.containsMouse ? Theme.hover : "transparent"`, and add to `PlaceRow`:

```qml
        onActiveChanged: if (active) root.activeRow = row
        Component.onCompleted: if (active) root.activeRow = row
```

   And in `Sidebar` root add, so leaving every place hides the pill:

```qml
    onActivePlaceChanged: if (activePlace === "") activeRow = null
```

- [ ] **Step 2: Glass tints change smoothly**

In `Glass.qml`, in the tint rectangle (`color: root.tint`), add:

```qml
        Behavior on color { ColorAnimation { duration: Theme.dur("effects") } }
```

- [ ] **Step 3: Search and path editing crossfade in the capsule**

In `Browser.qml`, inside `Glass { id: pathCapsule …`:

1. The accent border rectangle: replace `border.width: root.editingPath || root.searching ? 2 : 0; border.color: Theme.primary` with:

```qml
                        border.width: 2; border.color: Theme.primary
                        opacity: root.editingPath || root.searching ? 1 : 0
                        Behavior on opacity { Anim { kind: "effects" } }
```

2. `Flickable { id: crumbs …`: replace `visible: !root.editingPath && !root.searching` with:

```qml
                        opacity: root.editingPath || root.searching ? 0 : 1
                        visible: opacity > 0
                        Behavior on opacity { Anim { kind: "effects" } }
```

3. The editor `RowLayout` (with `TextInput { id: field`): replace `visible: root.editingPath || root.searching` with:

```qml
                        opacity: root.editingPath || root.searching ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { Anim { kind: "effects" } }
```

- [ ] **Step 4: Menus pop from the pointer; submenus slide**

In `Menu.qml`:

1. Add after `signal done()`:

```qml
    property point origin: Qt.point(0, 0)   // where it pops out from, in the menu's coordinates
    property real pop: 1
    transform: [
        Scale { origin.x: root.origin.x; origin.y: root.origin.y; xScale: root.pop; yScale: root.pop },
        Translate { id: slide }
    ]
    // Top-level menus pop from the pointer; submenus (parentMenu set before completion) slide in 8 px
    Component.onCompleted: {
        if (!Theme.animate) return;
        opacity = 0;
        if (parentMenu) { slide.x = -8; subIn.start(); } else { pop = 0.92; popIn.start(); }
    }
    ParallelAnimation {
        id: popIn
        Anim { target: root; property: "pop"; to: 1; kind: "fastSpatial" }
        Anim { target: root; property: "opacity"; to: 1; kind: "effects" }
    }
    ParallelAnimation {
        id: subIn
        Anim { target: slide; property: "x"; to: 0; kind: "fastSpatial" }
        Anim { target: root; property: "opacity"; to: 1; kind: "effects" }
    }
```

2. Make the submenu know it is one before it completes: in `Loader { id: subLoader …`, delete the line
   `source: "Menu.qml" // by URL: a component can't contain itself directly` and in `onLoaded` delete
   `item.width = 250;` and `item.parentMenu = root;`. In `function openSub(i)`, replace
   `subLoader.active = true;` with:

```qml
        // By URL (a component can't contain itself); initial properties are set before onCompleted runs
        subLoader.setSource("Menu.qml", { parentMenu: root, width: 250 });
        subLoader.active = true;
```

In `Browser.qml`, the menu `Loader { id: menuLoader … }`: add to the `Menu { … }` inside `sourceComponent`:

```qml
            origin: Qt.point(Math.max(0, Math.min(root.menuX - menuLoader.x, 300)), Math.max(0, root.menuY - menuLoader.y))
```

- [ ] **Step 5: The toast rises; the info panel slides in**

In `Browser.qml`, in `Glass { id: toast …`:

1. Replace `Behavior on opacity { NumberAnimation { duration: 160 } }` with:

```qml
                Behavior on opacity { Anim { kind: "effects" } }
                transform: Translate { id: toastLift }
                Anim { id: toastRise; target: toastLift; property: "y"; from: 16; to: 0; kind: "enter" }
```

2. In `function show(t, u, err)`, append `toastRise.restart();`.

In the `InfoPanel { … }` inside the main `RowLayout`, replace `visible: root.infoOpen` with:

```qml
            property real reveal: root.infoOpen ? 1 : 0
            Behavior on reveal { Anim { kind: "spatial" } }
            visible: reveal > 0
            opacity: Math.min(1, reveal)
            transform: Translate { x: (1 - Math.min(1, reveal)) * 40 }
```

- [ ] **Step 6: Tabs grow in; the active pill glides**

In `Browser.qml`, `Row { id: tabStrip …`:

1. Give the `Repeater` an id: `id: tabRepeater`.
2. In the tab delegate (`delegate: MouseArea { … readonly property bool on: …`), add `id: tabItem`, remove the
   `Glass { anchors.fill: parent; backdrop: view; visible: parent.on; tint: Theme.chromeStrong }` block and add:

```qml
                        transformOrigin: Item.Left
                        Component.onCompleted: if (Theme.animate && root.tabs.length > 1) { scale = 0.8; grow.start(); }
                        Anim { id: grow; target: tabItem; property: "scale"; to: 1; kind: "fastSpatial" }
```
3. Before `Row { id: tabStrip …`, add the shared pill, so it sits behind the tabs:

```qml
            // The active tab's glass pill: one pill that glides between tabs
            Glass {
                readonly property Item at: { void root.tabs.length; return tabRepeater.itemAt(root.tabIndex); }
                visible: at !== null
                backdrop: view
                tint: Theme.chromeStrong
                x: tabStrip.x + (at ? at.x : 0)
                y: tabStrip.y
                width: at ? at.width : 0
                height: 44
                Behavior on x { Anim { kind: "fastSpatial" } }
            }
```

- [ ] **Step 7: Check every chrome motion lands in its final state**

Run:
```bash
cd ~/VHyprland-End4-pC
tools/himeko-files/capture.sh /tmp/claude-1000/hf-chrome.png ~/Pictures/Wallpapers -- "select himeko_nova.jpg" "info true" "toast Moved_2_items" "menu item"
magick /tmp/claude-1000/hf-chrome.png -resize 1280x /tmp/claude-1000/hf-chrome-small.png
```
Expected: sidebar pill on Pictures; info panel fully in place and opaque; toast above the status capsule;
the menu fully opaque at full size. View the image.

- [ ] **Step 8: A menu clamped at the window edge still pops from inside itself**

Temporarily add to the `IpcHandler` in `Browser.qml`:

```qml
        function menuAt(xy: string): void { const p = xy.split(","); root.backgroundMenu(Number(p[0]), Number(p[1])); }
```

Run:
```bash
cd ~/VHyprland-End4-pC && tools/himeko-files/capture.sh /tmp/claude-1000/hf-edge.png ~/Pictures/Wallpapers -- "menuAt 1880,1100"
magick /tmp/claude-1000/hf-edge.png -resize 1280x /tmp/claude-1000/hf-edge-small.png
```
Expected: the menu fully inside the window near the bottom-right, at full size and opacity (origin clamped
by `Math.max(0, …)`/`Math.min(…, 300)`). View the image. Keep `menuAt` (it is a useful IPC call).

- [ ] **Step 9: Commit**

```bash
cd ~/VHyprland-End4-pC && ./sync.sh >/dev/null && git add -A
git commit -m "Himeko Files: chrome motion (gliding sidebar and tab pills, search crossfade, menu pop, toast, info panel)" && git push
```

---

### Task 7: Scroll edge effect

**Files:**
- Modify: `~/.config/hypr/custom/himeko-files/Browser.qml`

- [ ] **Step 1: Add the band**

In `Browser.qml`, inside `Rectangle { id: main …`, right after the `ParallelAnimation { id: navAnim … }` added
in Task 5 (so after the file view and before the toolbar), add:

```qml
            // Scroll edge effect (iOS): once content scrolls under the toolbar and tabs, it fades out first.
            // Opacity follows the scroll offset: 0 at rest, so the large title is never dimmed.
            Rectangle {
                readonly property var list: root.tab && root.tab.viewMode === "details" ? detailsView : iconView
                readonly property real chromeBottom: tabStrip.y + tabStrip.height
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: chromeBottom + 60
                // At rest contentY = originY - topMargin (the list header makes originY negative)
                opacity: Math.max(0, Math.min(1, (list.contentY - list.originY + list.topMargin) / 40))
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.alpha(Theme.surface, 0.95) }
                    GradientStop { position: 0.68; color: Theme.alpha(Theme.surface, 0.85) }
                    GradientStop { position: 1.0; color: Theme.alpha(Theme.surface, 0) }
                }
            }
```

(`0.68` ≈ `chromeBottom / height` at the default layout: 118 / 178.)

- [ ] **Step 2: Check at rest and scrolled**

Add to the `IpcHandler` in `Browser.qml`:

```qml
        function scroll(px: int): void { const l = root.tab.viewMode === "details" ? detailsView : iconView; l.contentY = l.originY - l.topMargin + px; }
```

Run:
```bash
cd ~/VHyprland-End4-pC
tools/himeko-files/capture.sh /tmp/claude-1000/hf-rest.png ~ && magick /tmp/claude-1000/hf-rest.png -crop 1892x320+0+0 -resize 1280x /tmp/claude-1000/hf-rest-top.png
tools/himeko-files/capture.sh /tmp/claude-1000/hf-scrolled.png ~ -- "scroll 260" && magick /tmp/claude-1000/hf-scrolled.png -crop 1892x320+0+0 -resize 1280x /tmp/claude-1000/hf-scrolled-top.png
```
Expected: in `hf-rest-top.png` the "Home" title is at full brightness; in `hf-scrolled-top.png` folder tiles
fade out above the tab row instead of showing crisp text behind the capsules. View both.

- [ ] **Step 3: Commit**

```bash
cd ~/VHyprland-End4-pC && ./sync.sh >/dev/null && git add -A
git commit -m "Himeko Files: scroll edge effect under the floating toolbar" && git push
```

---

### Task 8: Narrow windows

**Files:**
- Modify: `~/.config/hypr/custom/himeko-files/Browser.qml`

**Interfaces:**
- Consumes: `root.showMenu(x, y, quick, entries)` (existing), `root.tab.go(path)`.

- [ ] **Step 1: Collapse the breadcrumbs**

In `Browser.qml`, inside `Flickable { id: crumbs …`:

1. Move the crumb list into a property on the `Flickable`: add

```qml
                        readonly property var parts: {
                            if (!root.tab) return [];
                            const p = root.tab.path, out = [];
                            if (p.startsWith(Fs.home)) {
                                out.push({ label: "Home", path: Fs.home, icon: "home" });
                                let acc = Fs.home;
                                for (const s of p.slice(Fs.home.length).split("/").filter(x => x)) { acc += "/" + s; out.push({ label: s, path: acc }); }
                            } else {
                                out.push({ label: "", path: "/", icon: "hard_drive" });
                                let acc = "";
                                for (const s of p.split("/").filter(x => x)) { acc += "/" + s; out.push({ label: s, path: acc }); }
                            }
                            return out;
                        }
                        // Measured with an invisible row of plain texts; collapse when the real row wouldn't fit
                        readonly property bool collapse: parts.length > 3 && measure.implicitWidth > width
                        Row {
                            id: measure
                            visible: false
                            spacing: 22
                            Repeater { model: crumbs.parts; delegate: Text { required property var modelData; text: modelData.label || "XX"; font.family: Theme.font; font.pixelSize: 14; font.weight: 600 } }
                        }
```

   (`spacing: 22` + 20 px per crumb pill ≈ the real chevron and padding; the `Text` stands for each crumb.)
2. Replace the `Repeater`'s `model: { … }` block (the one that builds `parts` inline) with:

```qml
                                model: crumbs.collapse
                                    ? [crumbs.parts[0], { label: "…", path: "", ellipsis: true }].concat(crumbs.parts.slice(-2))
                                    : crumbs.parts
```

3. In the crumb `MouseArea`, replace `onClicked: last ? root.editingPath = true : root.tab.go(modelData.path)` with:

```qml
                                        onClicked: {
                                            if (modelData.ellipsis) {
                                                const p = mapToItem(root, 0, height + 6);
                                                root.showMenu(p.x, p.y, [], crumbs.parts.slice(1, -2).reverse().map(c => ({ icon: "folder", label: c.label, action: () => root.tab.go(c.path) })));
                                            } else if (last) root.editingPath = true;
                                            else root.tab.go(modelData.path);
                                        }
```

- [ ] **Step 2: Header filter collapses under 760 px**

In `Browser.qml`, `Component { id: headerComp` → its root `Item`:

1. Add `readonly property bool narrow: width < 760`.
2. Give the header `Item` an `id: header`. On the chips `Rectangle` (the one containing `Row { id: chips`),
   add `visible: !header.narrow`.
3. After that `Rectangle`, add:

```qml
                IconButton {
                    id: filterBtn
                    visible: header.narrow
                    implicitHeight: 44
                    icon: "filter_list"; tip: "Filter"
                    active: root.tab && root.tab.filter !== "all"
                    onClicked: {
                        const p = filterBtn.mapToItem(root, -150, 48);
                        const f = [["all", "All"], ["image", "Images"], ["video", "Videos"], ["doc", "Docs"]];
                        root.showMenu(p.x, p.y, [], f.map(x => ({ icon: root.tab.filter === x[0] ? "check" : "", label: x[1], action: () => root.tab.filter = x[0] })));
                    }
                }
```

4. On the sort `IconButton { id: sortBtn`, change `label: root.tab ? (… )[root.tab.sortKey] : ""` to
   `label: !header.narrow && root.tab ? ({ name: "Name", modified: "Modified", size: "Size", kind: "Kind" })[root.tab.sortKey] : ""`.

- [ ] **Step 3: Toolbar view toggle under 640 px**

In `Browser.qml`, on `Rectangle { id: main`, add `readonly property bool tight: width < 640`. In the toolbar's
view-mode `Glass` (the one with `Row { id: modeRow`), set `visible: !main.tight`, and after it add:

```qml
                Glass {
                    visible: main.tight
                    backdrop: view
                    implicitWidth: 52; implicitHeight: 52
                    IconButton {
                        anchors.centerIn: parent
                        icon: root.tab && root.tab.viewMode === "icons" ? "grid_view" : "view_list"
                        tip: root.tab && root.tab.viewMode === "icons" ? "Switch to details (Ctrl+2)" : "Switch to icons (Ctrl+1)"
                        onClicked: root.tab.viewMode = root.tab.viewMode === "icons" ? "details" : "icons"
                    }
                }
```

- [ ] **Step 4: Check at full width (nothing changed)**

Run:
```bash
cd ~/VHyprland-End4-pC && tools/himeko-files/capture.sh /tmp/claude-1000/hf-wide.png /usr/lib/x86_64-linux-gnu/gstreamer-1.0
magick /tmp/claude-1000/hf-wide.png -crop 1892x320+0+0 -resize 1280x /tmp/claude-1000/hf-wide-top.png
```
Expected: full breadcrumbs (`/ › usr › lib › x86_64-linux-gnu › gstreamer-1.0`), chips and sort label shown.
View the image.

- [ ] **Step 5: Check at 500 px on a deep path with long names**

Run:
```bash
cd ~/VHyprland-End4-pC && SIZE="500 900" tools/himeko-files/capture.sh /tmp/claude-1000/hf-narrow.png /usr/lib/x86_64-linux-gnu/gstreamer-1.0
```
Expected (view the image): sidebar is the icon rail; breadcrumbs read `/ › … › x86_64-linux-gnu › gstreamer-1.0`
(or ellipsized ends) without overlapping; one filter button instead of chips; the sort button is icon-only;
one view toggle button; nothing in the toolbar, header or tab row overlaps.

- [ ] **Step 6: Commit**

```bash
cd ~/VHyprland-End4-pC && ./sync.sh >/dev/null && git add -A
git commit -m "Himeko Files: narrow windows (breadcrumbs collapse, filter and view toggles)" && git push
```

---

### Task 9: Lighter thumbnails, debounced columns, final numbers

**Files:**
- Modify: `~/.config/hypr/custom/himeko-files/Thumb.qml`
- Modify: `~/.config/hypr/custom/himeko-files/IconGrid.qml`
- Modify: `README.md`

- [ ] **Step 1: Decode thumbnails at the size shown**

In `Thumb.qml`, replace `sourceSize.width: 256` with:

```qml
        // Decode at the size shown, in two buckets so zooming doesn't reload constantly (cache files stay 256 px)
        sourceSize.width: root.width <= 128 ? 128 : 256
```

- [ ] **Step 2: Columns follow the width after it settles**

In `IconGrid.qml`:

1. After `readonly property real usable: width - 2 * pad`, add:

```qml
    // Column counts follow the width 100 ms after it stops changing, so a resize or the info panel sliding in
    // doesn't rebuild every row each frame; tiles just stretch meanwhile.
    property real columnsWidth: usable
    Timer { id: settle; interval: 100; onTriggered: root.columnsWidth = root.usable }
    onUsableChanged: settle.restart()
```

2. In `folderCols` and `fileCols`, replace `usable` with `columnsWidth`:

```qml
    readonly property int folderCols: Math.max(1, Math.floor((columnsWidth + gap) / (230 + gap)))
    readonly property int fileCols: Math.max(1, Math.floor((columnsWidth + gap) / (tileW + gap)))
```

   (`thumbH` keeps using `usable` and `fileCols`, so tiles stretch with the live width.)

- [ ] **Step 3: Measure against the baseline**

Run:
```bash
cd ~/VHyprland-End4-pC
tools/himeko-files/capture.sh /tmp/claude-1000/hf-a2.png ~/Pictures/Wallpapers >/dev/null; sleep 5; tools/himeko-files/perf.sh 10
tools/himeko-files/capture.sh /tmp/claude-1000/hf-b2.png /usr/lib/x86_64-linux-gnu >/dev/null; sleep 5; tools/himeko-files/perf.sh 10
```
Expected: `idle_cpu_pct` below 0.5 on both lines, and each `rss_mb` at or below its Task 1 baseline. If RSS is
higher, find which task added it (revert one at a time) before going on.

- [ ] **Step 4: Note it in the README**

In `README.md`, in the "🗂️ Himeko Files" section, after the "**Keys**" bullet, add:

```markdown
- **Motion**: moves like the shell (end4-pC's curves); turns off with GNOME's "animations" switch or
  Hyprland's `animations:enabled`. Folder tiles show item counts; dates read like Nautilus ("3 days ago")
```

- [ ] **Step 5: Final self-check, then commit**

Run: `qs -p ~/.config/hypr/custom/himeko-files/selftest.qml 2>&1 | grep -E "FAIL|selftest:"`
Expected: `selftest: 0 failures`. Then kill the test instance and commit:

```bash
for pid in $(hyprctl clients -j | jq -r '.[] | select(.title|startswith("Files — ")) | .pid'); do kill "$pid"; done
cd ~/VHyprland-End4-pC && ./sync.sh >/dev/null && git add -A
git commit -m "Himeko Files: thumbnails decoded at shown size, debounced columns

After polish & motion:
  Wallpapers: <paste perf.sh line>
  3915-file folder: <paste perf.sh line>" && git push
```
