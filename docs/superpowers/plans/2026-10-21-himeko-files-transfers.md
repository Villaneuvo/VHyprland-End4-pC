# Himeko Files Transfers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drag and drop in and out of Himeko Files, with copies and moves that show progress, can be cancelled, and ask
on name conflicts (GNOME Files style).

**Architecture:**
- A new `transfer.py` helper (Python stdlib, plus `gio` for Trash) does every copy and move: it scans, writes hidden part
  files, reports progress, asks on conflicts, and keeps an undo log, all as JSON lines over stdin/stdout like
  `network.py`.
- `Fs` runs it as jobs (`Fs.jobs`), shown by an operations button and popover in the header. `ConflictDialog.qml`
  answers its questions.
- Qt Quick `Drag` (Automatic, `text/uri-list`) and `DropArea` on tiles, rows, the view, crumbs, tabs and sidebar feed
  one drop routine.

**Tech Stack:** Quickshell (QML, Qt 6), Python 3 stdlib, gio, bash.

**Spec:** `docs/superpowers/specs/2026-10-21-himeko-files-transfers-design.md`

## Global Constraints

- **Where things go:** app code lives in `~/.config/hypr/custom/himeko-files/`. `./sync.sh` copies it, then run
  `git reset -q` and add only this plan's files.
- **Commits:** on `main`, pushed per task. **No Co-Authored-By or AI attribution.**
- **No new dependencies.** No new polling: the progress cadence comes from the helper. The only timers are
  single-shot (spring-open on hover, job fade-out, autoscroll while dragging).
- **The window never does file I/O.** That includes the `st_dev` same-filesystem test, which runs in `transfer.py`.
- **`transfer.py` output:** `json.dumps(obj, ensure_ascii=False)`, one object per line.
  - Lines: `{"scanning": n}`, `{"total": bytes, "files": n}`, `{"progress": {"bytes": n, "file": name}}` (at most every
    150 ms), `{"ask": "conflict", "name", "dest", "isDir", "canTrash", "old": {"size", "mtime"}, "new": {"size", "mtime"}, "more": bool}`.
  - `{"made": [src, created]}` and `{"skipped": src}` per top-level source, and `{"failed": {"path", "error"}}` per
    failed item.
  - Undo log: `{"undo": {"created": path}}`, `{"undo": {"moved": [from, to]}}`,
    `{"undo": {"replaced": path, "trash": [trashDir, name]}}`.
  - End: `{"done": true, "failed": n}`, `{"error": msg}` or `{"cancelled": true}`.
  - Answers: `{"choice": "skip"|"keep"|"replace"|"merge", "all": bool}` or `{"cancel": true}`. End of input counts
    as cancel.
- **Part files** are `.NAME.himeko-part` in the target folder, renamed into place when complete.
- **Copy (exact strings):**
  - job titles: "Copying “a.txt” to “Pictures”", "Copying 12 files to “Pictures”" (all top-level sources are files),
    "Copying 3 items to “Pictures”" (otherwise); "Moving …" likewise; "Moving 3 items to Trash", "Deleting 3 items",
    "Compressing 3 items", "Extracting “x.zip”";
  - job subtitles: "Preparing…", "1.2 GB of 3.4 GB — 2 minutes left", "Done", "Copied 10 of 12 items";
  - conflicts: "Replace “name”?", "Merge Folder “name”?", "A file with the same name already exists in “Dest”.",
    "A folder with the same name already exists in “Dest”. Merging asks before replacing any files in it.",
    "There's no Trash here: the existing file will be overwritten.", "Original", "Replacement", "newer", "larger",
    "Apply to All", "Cancel", "Skip", "Keep Both", "Replace", "Merge";
  - closing: "Operations are running", "Cancel Them and Close", "Keep Open";
  - drop toast: "Only files can be dropped here".
- **Text:** file-derived text is `textFormat: Text.PlainText`.
- **Tests:**
  - helper tests use `$t` (`~/.cache`, ext4) and a `mktemp -d -p /tmp` folder (tmpfs, another filesystem), with
    `XDG_DATA_HOME=$t/xdg` so Trash is scratch;
  - server checks reuse Task 2 of the network plan's private bus (own config, no includes, never the keyring);
  - UI checks run on the headless output with `testdav.py` and the scratch env.
- **Suite:** `~/.config/hypr/custom/himeko-files/ops.sh selftest && qs -p ~/.config/hypr/custom/himeko-files/selftest.qml 2>&1 | grep -q 'selftest: 0 failures'`

## Review Focus

- **Cancel in the middle of a multi-item job with conflicts:** what finished stays, Undo covers exactly that, and no
  part file is left. Pinned in Task 2 Step 1 and Task 3 Step 4.
- **A folder dropped onto itself, its own subfolder, or the folder it's already in:** refused or a no-op, never a
  recursive copy. Pinned in Task 1 Step 1 and Task 6 Step 4.
- **A multi-gigabyte file cancelled halfway:** the part file goes at once, progress stays smooth, and the window
  doesn't stutter. Pinned in Task 1 Step 1 and Task 4 Step 3.
- **The window closed by the compositor mid-transfer:** the job finishes in the background, conflicts take Keep Both,
  the process quits after it, and there's no half file. Pinned in Task 4 Step 4.
- **URIs dropped from other apps:** `%20`, a trailing slash, `file://localhost/`, and a mix with `https://` links:
  decoded right, links ignored with the toast. Pinned in Task 3 Step 1 and Task 6 Step 4.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `…/transfer.py` | copy/move/auto with scan, progress, part files, conflicts, undo log, cancel | Create |
| `…/ops.sh` | dispatch `transfer`, `untrash`; drop `paste`; selftest | Modify |
| `…/places.py` | `bookmarks pin PATH [LABEL] [--at N]` (insert a pin among the shown ones) | Modify |
| `…/Fs.qml` | jobs, transfer wrapper, undo from the log, job rules, drop rules; trash/delete/zip/extract as jobs | Modify |
| `…/ConflictDialog.qml` | the conflict dialog | Create |
| `…/JobsButton.qml` | header button with progress ring + popover rows | Create |
| `…/ItemTile.qml`, `…/DetailsList.qml`, `…/IconGrid.qml` | drag source, folder drop targets, view drop, autoscroll | Modify |
| `…/Browser.qml` | drop routine, crumbs/tabs targets, close handling, IPC hooks | Modify |
| `…/Sidebar.qml` | row drop targets, pin insertion | Modify |
| `…/shell.qml` | window `onClosed` → finish jobs, then quit | Modify |
| `…/selftest.qml` | rules | Modify |
| `README.md` | Himeko Files bullets | Modify |

(`…` = `~/.config/hypr/custom/himeko-files`)

---

### Task 1: transfer.py: copy, move, auto, progress, cancel

**Interfaces — Produces:**
- `ops.sh transfer copy|move|auto DEST SRC…` emits the lines in Global Constraints. With no conflicts, nothing is read
  from stdin.
- `auto` moves an item when `os.stat(src).st_dev == os.stat(DEST).st_dev` and copies it otherwise.
- A move across filesystems copies, then removes the source only after its copy completed.
- `copy` keeps symlinks as links. On local disks it keeps times and modes (`shutil.copystat`). Under
  `$XDG_RUNTIME_DIR/gvfs` it copies data only.
- Data is copied in 1 MiB blocks, with `os.copy_file_range` where it works and read/write otherwise.
- `SIGTERM` ends the current block, removes the part file, and ends with `{"cancelled": true}`.
- Test hook: `HF_SLOW_COPY=SECONDS` sleeps that long after each block.

- [ ] **Step 1: Write failing checks** in `ops.sh selftest`, before `exit $fail`:

```bash
    # ---- transfers: transfer.py ----
    X=$(mktemp -d -p /tmp); mkdir -p "$t/tr/src/tree/deep" "$t/tr/dst"
    head -c 300000 /dev/urandom >"$t/tr/src/tree/big.bin"; echo a >"$t/tr/src/tree/deep/a.txt"; ln -s deep/a.txt "$t/tr/src/tree/link"
    "$me" transfer copy "$t/tr/dst" "$t/tr/src/tree" </dev/null >"$t/tr/o1"
    check "transfer: total counts regular files" "$(grep -o '"total": [0-9]*' "$t/tr/o1")" '"total": 300002'
    check "transfer: copy is exact, links stay links" "$(cmp -s "$t/tr/src/tree/big.bin" "$t/tr/dst/tree/big.bin" && readlink "$t/tr/dst/tree/link")" "deep/a.txt"
    check "transfer: made + done" "$(grep -c "\"made\": \[\"$t/tr/src/tree\", \"$t/tr/dst/tree\"\]" "$t/tr/o1")$(tail -1 "$t/tr/o1")" '1{"done": true, "failed": 0}'
    "$me" transfer auto "$X" "$t/tr/src/tree/deep/a.txt" </dev/null >/dev/null
    check "transfer auto: another filesystem copies" "$(test -e "$t/tr/src/tree/deep/a.txt" && cat "$X/a.txt")" "a"
    "$me" transfer auto "$t/tr/dst" "$t/tr/src/tree/deep" </dev/null >"$t/tr/o2"
    check "transfer auto: same filesystem moves" "$(test -e "$t/tr/src/tree/deep" || echo gone)$(grep -c '"undo": {"moved"' "$t/tr/o2")" "gone1"
    "$me" transfer move "$X" "$t/tr/src/tree/big.bin" </dev/null >/dev/null
    check "transfer move across filesystems: copy then remove" "$(test -e "$t/tr/src/tree/big.bin" || echo gone)$(cmp -s "$t/tr/dst/tree/big.bin" "$X/big.bin" && echo same)" "gonesame"
    check "transfer: a folder into itself is refused" "$("$me" transfer copy "$t/tr/dst/tree/deep" "$t/tr/dst/tree" </dev/null | grep -c '"failed"')$(test -e "$t/tr/dst/tree/deep/tree" || echo none)" "1none"
    check "transfer: into the folder it's in does nothing" "$("$me" transfer move "$t/tr/dst" "$t/tr/dst/tree" </dev/null | grep -c '"skipped"')" "1"
    mkdir -p "$t/tr/lock"; echo s >"$t/tr/lock/secret"; chmod 000 "$t/tr/lock/secret"; echo ok >"$t/tr/lock/fine"
    "$me" transfer copy "$X" "$t/tr/lock" </dev/null >"$t/tr/o3"; chmod 600 "$t/tr/lock/secret"
    check "transfer: one failed item, the rest goes on" "$(grep -c '"failed": {' "$t/tr/o3")$(cat "$X/lock/fine")$(tail -1 "$t/tr/o3")" '1ok{"done": true, "failed": 1}'
    head -c 3000000 /dev/zero >"$t/tr/slow.bin"
    HF_SLOW_COPY=0.05 "$me" transfer copy "$X" "$t/tr/slow.bin" </dev/null >"$t/tr/o4" & tp=$!; sleep 0.6
    check "transfer: writes a hidden part file" "$(test -e "$X/.slow.bin.himeko-part" && echo part)$(test -e "$X/slow.bin" || echo none)" "partnone"
    kill -TERM $tp; wait $tp
    check "transfer: cancel removes the part file" "$(ls -A "$X" | grep -c himeko-part)$(tail -1 "$t/tr/o4")" '0{"cancelled": true}'
    check "transfer: progress lines while copying" "$(( $(grep -c '"progress"' "$t/tr/o4") > 2 ))" "1"
    rm -rf "$X"
```

- [ ] **Step 2: Run** `ops.sh selftest`. Expected: these FAIL (`transfer` is unknown).
- [ ] **Step 3: Implement** `transfer.py` per the Interfaces. Notes:
  - `ops.sh`: `transfer) exec python3 -I "$(dirname -- "$0")/transfer.py" "$@" ;;`.
  - Target names come from `ops.sh unique`'s rule, reimplemented: "name (2).ext", with `.tar.gz` kept whole. Keep Both
    uses it from Task 2 on.
  - Into itself: `{"failed": {"path": src, "error": "Can't put a folder inside itself"}}`.
  - "No space left" (`errno.ENOSPC`) ends with `{"error": "Not enough free space in “<dest name>”"}`.
- [ ] **Step 4: Run** `ops.sh selftest`. Expected: all ok.
- [ ] **Step 5: Commit** `"Himeko Files: transfer helper (progress, part files, cancel)"`, then push.

---

### Task 2: transfer.py: conflicts, Trash for replaced items, undo log

**Interfaces — Produces:**
- **Conflict ask:** on a taken name, ask one conflict (Global Constraints). `canTrash` is
  `Gio.File.query_info("access::can-trash")` on the existing item (`gi`), with False when it can't be read. `more`
  says whether sources are left after this one. An `"all": true` answer applies the choice to every later conflict of
  the same kind (file/folder).
- **Replace** (and Replace inside a merge) where `canTrash` is true calls `Gio.File.trash()` on the old item before
  writing. It then finds its name in the right Trash's `info/*.trashinfo` (`Path=` the original, newest first): the
  home Trash (`$XDG_DATA_HOME/Trash`) when on its device, otherwise `$topdir/.Trash-$UID`. It emits
  `{"undo": {"replaced": path, "trash": [trashDir, name]}}`. Without a Trash it overwrites.
- **Merge** recurses into the existing folder. Every item it creates emits `{"undo": {"created": …}}`.
- `ops.sh untrash TRASHDIR NAME` moves `TRASHDIR/files/NAME` back to the `Path=` in `TRASHDIR/info/NAME.trashinfo` and
  deletes the info file. It refuses if something exists there.

- [ ] **Step 1: Write failing checks** in `ops.sh selftest`:

```bash
    # ---- transfers: conflicts ----
    export XDG_DATA_HOME=$t/xdg; C=$t/cf; mkdir -p "$C/a/d" "$C/b/d"
    echo new >"$C/a/f.txt"; echo old >"$C/b/f.txt"; echo n1 >"$C/a/d/x"; echo o1 >"$C/b/d/x"; echo n2 >"$C/a/d/y"
    echo '{"choice": "skip"}' | "$me" transfer copy "$C/b" "$C/a/f.txt" >"$C/o1"
    check "conflict: asks, skip keeps the old" "$(grep -c '"ask": "conflict"' "$C/o1")$(cat "$C/b/f.txt")$(grep -c '"skipped"' "$C/o1")" "1old1"
    echo '{"choice": "keep"}' | "$me" transfer copy "$C/b" "$C/a/f.txt" >/dev/null
    check "conflict: keep both" "$(cat "$C/b/f (2).txt")" "new"
    echo '{"choice": "replace"}' | "$me" transfer copy "$C/b" "$C/a/f.txt" >"$C/o2"
    check "conflict: replace sends the old one to Trash" "$(cat "$C/b/f.txt")$(cat "$XDG_DATA_HOME"/Trash/files/f.txt*)" "newold"
    tr=$(grep -o '"trash": \[[^]]*\]' "$C/o2" | python3 -I -c 'import json,sys; print("\t".join(json.loads("{"+sys.stdin.read()+"}")["trash"]))')
    rm "$C/b/f.txt"; "$me" untrash $tr
    check "untrash puts the original back" "$(cat "$C/b/f.txt")" "old"
    printf '%s\n' '{"choice": "merge"}' '{"choice": "replace"}' | "$me" transfer copy "$C/b" "$C/a/d" >"$C/o3"
    check "conflict: merge asks again inside, creates the rest" "$(grep -c '"ask"' "$C/o3")$(cat "$C/b/d/x" "$C/b/d/y" | tr -d '\n')$(grep -c "\"created\": \"$C/b/d/y\"" "$C/o3")" "2n1n21"
    echo n3 >"$C/a/g.txt"; echo o3 >"$C/b/g.txt"
    echo '{"choice": "skip", "all": true}' | "$me" transfer copy "$C/b" "$C/a/f.txt" "$C/a/g.txt" >"$C/o4"
    check "conflict: apply to all asks once" "$(grep -c '"ask"' "$C/o4")$(grep -c '"more": true' "$C/o4")" "11"
    echo '{"cancel": true}' | "$me" transfer copy "$C/b" "$C/a/f.txt" >"$C/o5"
    check "conflict: cancel stops, nothing written" "$(tail -1 "$C/o5")$(ls -A "$C/b" | grep -c himeko-part)" '{"cancelled": true}0'
    unset XDG_DATA_HOME
```

  Plus, in the network plan's private-bus block, after its paste check: answer `{"choice": "replace"}` to
  `transfer copy` of `up.txt` onto the server again. Check that the ask says `"canTrash": false` and that the file is
  overwritten.

- [ ] **Step 2: Run** `ops.sh selftest`. Expected: these FAIL. Without conflict handling the second copy keeps both
  silently or errors, and `untrash` is unknown.
- [ ] **Step 3: Implement** per the Interfaces.
- [ ] **Step 4: Run** `ops.sh selftest`. Expected: all ok, and the real `~/.local/share/Trash` is untouched (count
  before and after).
- [ ] **Step 5: Commit** `"Himeko Files: transfer conflicts and undo log"`, then push.

---

### Task 3: Fs: jobs, transfers, undo from the log, rules

**Interfaces — Produces:**
- **Jobs:**
  - `Fs.jobs` is a list of `{ id, kind ("copy"|"move"|"trash"|"delete"|"compress"|"extract"), names, dest, bytes,
    total, files, started, state ("scanning"|"running"|"done"|"failed"|"cancelled"), failed: [{path, error}], made }`.
  - `Fs.jobsActive: int`.
  - `Fs.cancelJob(id)` sends SIGTERM to a transfer (`running = false` on its Process, after setting a flag so the
    result reads as cancelled).
- **Transfers:**
  - `Fs.transfer(mode, dest, paths)` replaces `doPaste` and is what paste and drops call. On done it toasts
    "Copied N items" or "Moved N items" with Undo.
  - `undoAction = { kind: "log", steps: Fs.undoPlan(log) }`.
  - signal `Fs.transferAsk(var req)` carries the conflict ask plus `reply(answer)` and `owner`, and
    `Fs.transferAskGone(int owner)`, the same shape as `netAsk`.
- **Other jobs:** `trash`, `deleteForever`, `compress` and `extract` also register a job (indeterminate, no bytes).
- **Pure rules:**
  - `Fs.undoPlan(log)` returns steps in reverse order: `{op: "remove", path}`, `{op: "moveBack", from, to}`,
    `{op: "untrash", dir, name}`;
  - `Fs.jobTitle(job)`;
  - `Fs.jobProgress(done, total, elapsedMs)`;
  - `Fs.dropPaths(uris)` returns `{paths, ignored}`;
  - `Fs.dropAction(paths, dest)` returns `"none"|"trash"|"transfer"`.
- **Removed:** `ops.sh paste`, `Fs.doPaste`, `Fs.pastePairs` and their selftest checks. The transfer checks replace
  them.

- [ ] **Step 1: Write failing checks** in `selftest.qml`:

```js
        // ---- transfer rules ----
        check("jobTitle: one", Fs.jobTitle({ kind: "copy", names: ["a.txt"], dest: "/h/Pictures", allFiles: true }), "Copying “a.txt” to “Pictures”");
        check("jobTitle: files", Fs.jobTitle({ kind: "copy", names: ["a", "b"], dest: "/h/Pictures", allFiles: true }), "Copying 2 files to “Pictures”");
        check("jobTitle: items", Fs.jobTitle({ kind: "move", names: ["a", "b", "c"], dest: "/h/Pictures", allFiles: false }), "Moving 3 items to “Pictures”");
        check("jobTitle: trash", Fs.jobTitle({ kind: "trash", names: ["a", "b", "c"] }), "Moving 3 items to Trash");
        check("jobTitle: extract", Fs.jobTitle({ kind: "extract", names: ["x.zip"] }), "Extracting “x.zip”");
        check("jobProgress: preparing", Fs.jobProgress(0, 0, 0), "Preparing…");
        check("jobProgress: no estimate yet", Fs.jobProgress(12582912, 3650722202, 1000), "12 MB of 3.4 GB");
        check("jobProgress: minutes", Fs.jobProgress(1288490189, 3650722202, 60000), "1.2 GB of 3.4 GB — 2 minutes left");
        check("jobProgress: under a minute", Fs.jobProgress(3000000000, 3650722202, 60000), "2.8 GB of 3.4 GB — less than a minute left");
        check("undoPlan", Fs.undoPlan([{ created: "/d/a" }, { moved: ["/s/b", "/d/b"] }, { replaced: "/d/c", trash: ["/T", "c.2"] }]),
              [{ op: "untrash", dir: "/T", name: "c.2" }, { op: "moveBack", from: "/d/b", to: "/s/b" }, { op: "remove", path: "/d/a" }]);
        check("dropPaths", Fs.dropPaths(["file:///h/a%20b.txt", "https://x.org/i.png", "file:///h/dir/", "file://localhost/h/c"]),
              { paths: ["/h/a b.txt", "/h/dir", "/h/c"], ignored: 1 });
        check("dropAction: same folder", Fs.dropAction(["/h/d/a", "/h/d/b"], "/h/d"), "none");
        check("dropAction: trash", Fs.dropAction(["/h/d/a"], Fs.trashDir), "trash");
        check("dropAction: elsewhere", Fs.dropAction(["/h/d/a"], "/h/e"), "transfer");
```

- [ ] **Step 2: Run** `selftest.qml`. Expected: FAIL (`jobTitle` is not a function).
- [ ] **Step 3: Implement** in `Fs.qml`:
  - Jobs ride the `talk()`-style Process: stdin open, `SplitParser`, JSON per line.
  - `undo()` gains `kind: "log"`: a step on a remote path deletes (`rm -rf`) instead of trashing, and `untrash` runs
    `ops.sh untrash`.
  - Jobs that ended `done` leave `Fs.jobs` 3 s later (single-shot Timer per job). Failed jobs stay until
    `Fs.dismissJob(id)`.
  - Paste and the IPC `pasteHere` go through `transfer`. Remove `ops.sh paste`, `doPaste` and `pastePairs`.
- [ ] **Step 4: Check headless:**
  - Paste a 3 MB file with `HF_SLOW_COPY=0.05` in `HF_ENV`. `Fs.jobs` (IPC `jobsState()` → JSON) shows `running`
    with bytes rising.
  - IPC `cancelJob(id)`: the state becomes `cancelled`, no part file is left, and Undo removes whatever had already
    finished.
  - Paste the same two files twice and answer IPC `conflictAnswer("keep", true)`: one ask, both kept.
- [ ] **Step 5: Run the suite.** Commit `"Himeko Files: transfers as jobs, undo from the log"`, then push.

---

### Task 4: Operations button and popover, closing with jobs

**Files:** Create `JobsButton.qml`. Modify `Browser.qml`, `shell.qml`.

- [ ] **Step 1: JobsButton** sits in the header left of search, visible while `Fs.jobs.length > 0`.
  - **Ring:** a ring (Canvas or a `Shape` arc) whose sweep is Σbytes/Σtotal over running jobs. It spins
    (indeterminate) while any job is scanning or has no total. The center icon is `arrow_downward`, or `delete` when
    only trash/delete jobs run, or `check` when all are done.
  - **Popover:** a glass popover under it with one boxed row per job:
    - the title (`Fs.jobTitle`);
    - the subtitle (`Fs.jobProgress`, "Done", the failures summary "Copied 10 of 12 items" plus up to 3
      "name — reason" lines, or the error);
    - a 4 px progress bar;
    - ✕ (`Fs.cancelJob`) while it runs, or a dismiss button when it failed.

  The "Copying N items…" toast is removed.
- [ ] **Step 2: Closing.**
  - **In-app close:** closing the last tab or Ctrl+W on it while `Fs.jobsActive > 0` asks with the question dialog
    from the network plan (`AuthDialog` question mode, through `Fs.netAsk`-style req): "Operations are running" /
    "Cancel Them and Close" / "Keep Open".
  - **Compositor close:** `shell.qml` `FloatingWindow.onClosed` calls `browser.windowClosed()`. It quits at once when
    idle. Otherwise it sets `Fs.unattended = true`, which makes transfers answer conflicts with
    `{"choice": "keep", "all": true}`, and quits when `Fs.jobsActive` reaches 0.
- [ ] **Step 3: Check headless:**
  - Capture during a throttled copy: the ring partly full, the popover row with bytes and time left.
  - Capture at the end: the check, then gone after 3 s.
  - Capture a failed job: the unreadable file case, whose row stays.
  - Capture at 500 px.
- [ ] **Step 4: Review focus: compositor close.**
  - Start a throttled copy of 2 files, one of them conflicting. Close the test window with `hyprctl dispatch
    closewindow pid:<test pid>`, which only touches the test window.
  - The `qs` process keeps running until the copy finishes, then exits.
  - Both files exist (the conflict kept as "name (2)"), and no part file is left.
- [ ] **Step 5: Run the suite.** Commit `"Himeko Files: operations button and popover"`, then push.

---

### Task 5: Conflict dialog

**Files:** Create `ConflictDialog.qml`. Modify `Browser.qml`.

- [ ] **Step 1: ConflictDialog**, the same family as `AuthDialog`: glass card, modal, takes every key.
  - **Title and message** per the spec, with the no-Trash line when `!canTrash`.
  - **Comparison:** two boxed rows, Original and Replacement, each with an icon (`Fs.iconOf` by name), "size ·
    modified" (`Fs.size`, `Fs.date`), and a dim "newer"/"larger" tag on the side that is.
  - **Apply to All:** a switch row, shown when `more`.
  - **Buttons:** Cancel / Skip / Keep Both / Replace or Merge (danger style). Enter is Keep Both, Esc is Cancel.
  - Browser queues `Fs.transferAsk` like `asks`, and drops a queue entry on `transferAskGone`.
  - IPC: `conflictState()` gives JSON of what it shows; `conflictAnswer(choice, all)` presses a button.
- [ ] **Step 2: Check headless (captures):**
  - a file conflict with Apply to All (two clashing files), and one without (a single file);
  - a folder conflict (Merge);
  - a server conflict (`canTrash` false, so the overwrite line shows);
  - Enter keeps both, and Esc cancels the job.
- [ ] **Step 3: Run the suite.** Commit `"Himeko Files: conflict dialog"`, then push.

---

### Task 6: Dragging and dropping in the views

**Files:** Modify `ItemTile.qml`, `DetailsList.qml`, `IconGrid.qml`, `Browser.qml`.

**Interfaces — Produces:**
- `Browser.dropOn(destDir: string, uris: var)` is the one routine every drop calls:
  1. `Fs.dropPaths`; ignored links give the toast "Only files can be dropped here".
  2. `Fs.dropAction`.
  3. `Fs.trash(paths)`, `Fs.transfer("auto", destDir, paths)`, or nothing.
- `Browser.dragTarget: string` is the hovered target's key, for highlights. A single-shot 800 ms Timer spring-opens
  folders.
- IPC:
  - `dropUris(target: string, uris: string)`: `target` is a folder path or `"trash"`; `uris` are `|`-separated;
  - `dragHover(target: string)`: `""` ends it.

- [ ] **Step 1: Drag source** on tiles and rows: `DragHandler` (`target: null`) plus `Drag.dragType: Drag.Automatic`,
  with `Drag.mimeData: { "text/uri-list": uris }` and `Drag.supportedActions: Qt.CopyAction | Qt.MoveAction`.
  - Pressing an unselected item selects it alone first.
  - `Drag.imageSource` comes from `grabToImage` of a small badge: the first item's `Thumb` plus a cookie count when
    there are several.
  - If `DragHandler` fights the tile's `MouseArea` (clicks stop working), use the `MouseArea.drag.target` proxy item
    instead, and ledger it.
- [ ] **Step 2: Drop targets:**
  - **Folder tiles and rows:** a `DropArea` whose `keys: ["text/uri-list"]` hover sets `dragTarget`, gives a primary
    outline, and starts the spring timer.
  - **The view background:** drops go into `tab.path` (not in virtual places), with a soft primary border around the
    view.
  - **Autoscroll:** within 48 px of the view's top or bottom edge while dragging, scroll 12 px per frame (single-shot
    timer re-armed while inside).
- [ ] **Step 3: Check headless** (IPC; a pointer drag can't be faked off-screen):
  - `dragHover <folder>` shows the outline (capture), and the folder opens after 800 ms.
  - `dropUris <folder> "file://…|file://…"` runs a job, and the files land.
  - `dropUris trash …` trashes them, with Undo.
- [ ] **Step 4: Review focus.**
  - `dropUris` of a folder onto its own subfolder: refused (failed row), nothing copied.
  - Onto the folder it's in: nothing happens.
  - A mixed `file:///…a%20b.txt|https://x.org/i.png` drop: the file transfers, plus the toast.
- [ ] **Step 5: Run the suite.** Commit `"Himeko Files: drag and drop in the views"`, then push.

---

### Task 7: Sidebar, breadcrumbs, tabs as drop targets; pinning by drop

**Files:** Modify `Sidebar.qml`, `Browser.qml`, `places.py`, `ops.sh` (selftest).

**Interfaces — Produces:**
- `ops.sh bookmarks pin PATH [LABEL] [--at N]`, where N is the index among shown pins (0 = first).
- `Fs.pin(target, at)` passes it through.

- [ ] **Step 1: Failing check** (ops selftest):

```bash
    export XDG_CONFIG_HOME=$t/cfg3; mkdir -p "$t/p1" "$t/p2" "$t/p3"
    "$me" bookmarks pin "$t/p1"; "$me" bookmarks pin "$t/p2"; "$me" bookmarks pin "$t/p3" --at 1
    check "bookmarks pin --at" "$(sed "s|file://$t/||" "$t/cfg3/gtk-3.0/bookmarks" | tr '\n' ' ')" "p1 p3 p2 "
    unset XDG_CONFIG_HOME
```

- [ ] **Step 2: Run.** Expected: FAIL (`--at` is taken as the label). **Implement** `--at` in places.py. **Run.**
  Expected: ok.
- [ ] **Step 3: Targets:**
  - **Sidebar rows:** Home, local pins, drives with a mount, Connected servers, and network pins whose address is
    connected all take drops into their folder; Trash trashes. Each gets a highlight and spring-opens after 800 ms.
    Recent, Starred and Network take no drops.
  - **Pin insertion:** a thin `DropArea` between pins, and below the last one, accepts a single folder. It shows a
    2 px primary line and calls `Fs.pin(path, index)`.
  - **Breadcrumbs:** drop into the crumb's path, highlight, spring-open.
  - **Tabs:** highlight, switch after 800 ms, and a drop goes into the tab's path (not virtual).
- [ ] **Step 4: Check headless:**
  - `dragHover` on a pin, a crumb and a tab (captures). The tab switches after 800 ms.
  - `dropUris` onto a pin's path and onto `"trash"`.
  - IPC `pinDrop(path, index)` (the same function as the gap's drop) puts the pin at that index.
- [ ] **Step 5: Run the suite.** Commit `"Himeko Files: drop onto the sidebar, crumbs and tabs"`, then push.

---

### Task 8: Finish

- [ ] **Step 1: Perf** on `~/Pictures/Wallpapers`, settled: RSS within noise of 265–267 MB, idle CPU 0–0.2 %, and
  no new idle children. JobsButton and its popover aren't created until a job exists (`Loader`).
- [ ] **Step 2: README:**
  - add `- **Copy, move, drag and drop**: drag files onto folders, the sidebar, tabs or other apps; long copies show progress and can be cancelled; name clashes ask (Skip, Keep Both, Replace to Trash, Merge).`;
  - change "It never overwrites: clashing names become "name (2)"" to "Clashing names ask: Skip, Keep Both or Replace
    (the old one goes to Trash)";
  - remove "drag and drop" from "Not there yet".
- [ ] **Step 3: `done.sh`; the suite; real files untouched** (bookmarks, the real Trash count, the keyring mtime).
  Commit `"Himeko Files: transfers finished"` with the perf lines, then push.
- [ ] **Step 4: Ask the user to try real mouse drags:** within the window, from Dolphin into Himeko, and from Himeko
  into Chrome. This is the one check a pointer must do. The final report says so.
