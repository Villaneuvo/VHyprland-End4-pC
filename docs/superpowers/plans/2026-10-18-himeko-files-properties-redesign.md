# Himeko Files Properties Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the Properties card in GNOME Files 47's layout (hero, boxed lists, pages, popover dropdowns) and add
group change and "Change Permissions for Enclosed Files".

**Architecture:** Two shared row/group components (`PropRow.qml`, `PropGroup.qml`) and one popover owned by
`Properties.qml`, which becomes a small page stack (main, Permissions, Enclosed, Open With, Details). Data and guards
stay where they are; new system calls (`chgrp`, `chmodtree`, `umask`, `groups`) go in `ops.sh`, new pure rules in `Fs`.

**Tech Stack:** Quickshell (QML, Qt 6), bash, coreutils/findutils.

**Spec:** `docs/superpowers/specs/2026-10-18-himeko-files-properties-redesign.md` (follows
`docs/superpowers/specs/2026-10-18-himeko-files-properties-design.md`).

## Global Constraints

- App code live in `~/.config/hypr/custom/himeko-files/`; `cd ~/VHyprland-End4-pC && ./sync.sh` copies it. Commit on
  `main`, push per task, **no Co-Authored-By / AI attribution**.
- Everything from the first Properties version keeps working: live count killed on close, stale-answer guards, the
  permission click queue, Trash = no rename/permissions/open-with, plain text for file-derived text, sandboxed meta.
- Card ~460 px wide, ≤ 86 % of the window; boxed groups radius 14, rows ≥ 52 px, row surface `Theme.alpha(Theme.text,
  0.05)` (hover 0.08), 2 px between rows, 12 px between groups.
- Level labels in title case as in the recording: files "None / Read-Only / Read and Write"; folders "None / List Files
  Only / Access Files / Create and Delete Files"; Owner never offers "None".
- Motion: pages slide x +40 → 0 with fade (`spatial`), popovers scale 0.94 → 1 + fade (`fastSpatial`); nothing animates
  with `Theme.animate` false; no height animation.
- Tests on the headless output only (`tools/himeko-files/capture.sh` …, then `done.sh`), `qs ipc --pid <test pid>`;
  never `qs -p` a component file. Enclosed/chgrp tests only on scratch trees.
- Suite: `~/.config/hypr/custom/himeko-files/ops.sh selftest && qs -p ~/.config/hypr/custom/himeko-files/selftest.qml 2>&1 | grep -q 'selftest: 0 failures'`

## Review Focus

- **Enclosed on a mixed tree** (files you don't own, symlinks to elsewhere, an executable, a deep tree): only your
  items change, symlinks and their targets untouched, the executable stays executable, skipped count reported; closing
  the card mid-run doesn't cancel or break it. Pinned in Task 1 Step 1 and Task 5 Step 4.
- **Popover near the bottom edge or in a 500 px window**: it stays inside the window (opens upward when needed). Pinned
  in Task 4 Step 6.
- **Esc order**: popover first, then the page, then the card; Esc in the rename field only cancels the rename. Pinned in
  Task 4 Step 6 (via `propsBack`, the function Esc calls).
- **Group change you can't make** (not your file, a group you're not in): no dropdown for others' files; a failing chgrp
  toasts and the row shows the real group. Pinned in Task 4 Step 4.
- **Several items with both kinds**: Files/Folders rows on the Permissions page, no Enclosed row, each change touches
  its class only. Pinned in Task 4 Step 5.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `…/ops.sh` | `chgrp`, `chmodtree`, `umask`, `groups`; selftest | Modify |
| `…/Fs.qml` | title-case levels, `levelsFor`, `umaskLevels`, `symbolic`, wrappers `chgrp`, `chmodTree`, `groups`, `umask` | Modify |
| `…/selftest.qml` | new rules, updated level texts | Modify |
| `…/PropRow.qml` | one boxed-list row: `property` / `nav` / `dropdown` / `switch` / `button` kinds | Create |
| `…/PropGroup.qml` | rounded group of rows with an optional section title | Create |
| `…/Properties.qml` | header bar, page stack + slide, hero main page, popover, keys | Modify (rewrite of the view half) |
| `…/PropsPermissions.qml` | Permissions page | Rewrite |
| `…/PropsEnclosed.qml` | Enclosed page | Create |
| `…/PropsOpenWith.qml`, `…/PropsDetails.qml` | pages in the boxed style | Rewrite |
| `…/Browser.qml` | IPC: `propsPage`, `propsBack`, `propsOpen`, `propsPick`, `propsGroup`, `propsEnclosed`, `propsEnclosedApply`; state fields | Modify |

(`…` = `~/.config/hypr/custom/himeko-files`)

---

### Task 1: ops.sh — chgrp, chmodtree, umask, groups

**Interfaces — Produces:** `ops.sh chgrp GROUP PATH...` (skips symlinks; exit 1 if any failed).
`ops.sh chmodtree DIR FILESYM DIRSYM` → applies symbolic modes to everything under DIR (not DIR itself) that you own:
regular files get FILESYM, folders DIRSYM; never follows or changes symlinks; prints `changed<TAB>skipped` (skipped =
items under DIR you don't own). `ops.sh umask` → the octal umask, e.g. `0002`. `ops.sh groups` → your group names,
one per line.

- [ ] **Step 1: Write failing selftest checks** (before the final `exit $fail`):

```bash
    # ---- properties redesign: chgrp, chmodtree, umask, groups ----
    g=$(id -gn); printf 'x' >"$t/cg.txt"
    "$me" chgrp "$g" "$t/cg.txt"; check "chgrp own group" "$?" "0"
    check "chgrp result" "$(stat -c %G "$t/cg.txt")" "$g"
    check "groups lists mine" "$("$me" groups | grep -cx "$g")" "1"
    check "umask" "$("$me" umask)" "$(umask)"
    mkdir -p "$t/tree/sub"; printf 'a' >"$t/tree/f"; printf 'b' >"$t/tree/sub/g"; printf '#!/bin/sh\n' >"$t/tree/run.sh"
    chmod 600 "$t/tree/f" "$t/tree/sub/g"; chmod 700 "$t/tree/run.sh" "$t/tree/sub"; printf 't' >"$t/target"; chmod 600 "$t/target"
    ln -s "$t/target" "$t/tree/link"; tm=$(stat -c %a "$t/tree")
    out=$("$me" chmodtree "$t/tree" "g+r,g-w,o+r,o-w" "g+rx,g-w,o+rx,o-w")
    check "chmodtree files" "$(stat -c %a "$t/tree/f" "$t/tree/sub/g" | tr '\n' ' ')" "644 644 "
    check "chmodtree keeps x" "$(stat -c %a "$t/tree/run.sh")" "744"
    check "chmodtree folders" "$(stat -c %a "$t/tree/sub")" "755"
    check "chmodtree not the folder itself" "$(stat -c %a "$t/tree")" "$tm"
    check "chmodtree leaves link targets" "$(stat -c %a "$t/target")" "600"
    check "chmodtree output" "$out" "4"$'\t'"0"
```

- [ ] **Step 2: Run** selftest — Expected: the new checks FAIL (usage), the rest ok.
- [ ] **Step 3: Implement.** `chgrp`: skip `-L`, `chgrp -- GROUP PATH`. `chmodtree`: `find DIR -mindepth 1 -user "$(id -u)"
  \( -type f -exec chmod FILESYM {} + -printf x \) -o \( -type d -exec … \)` — or two finds — and count with `-printf`
  (changed = owned files+dirs, skipped = `find DIR -mindepth 1 ! -user "$(id -u)" ! -type l | wc -l`); symlinks
  excluded by `-type f/-type d` (find doesn't follow by default). `umask`: `umask`. `groups`: `id -nG | tr ' ' '\n'`.
- [ ] **Step 4: Run** selftest — Expected: all `ok`.
- [ ] **Step 5: Commit** — `"Himeko Files: ops for group change and enclosed permissions"`; push.

---

### Task 2: Fs rules

**Interfaces — Produces:** level texts in title case (`fileLevels`, `dirLevels`, `fileBits`, `dirBits` keys);
`Fs.levelsFor(who: "u"|"g"|"o", isDir): var` (Owner without "None"); `Fs.umaskLevels(umask: int): var` →
`{ files: {u,g,o}, folders: {u,g,o} }` (via `accessOf(0o666 & ~umask, …, false)` / `accessOf(0o777 & ~umask, …, true)`);
`Fs.symbolic(who, level, isDir): string` and `Fs.symbolicAll(levels: {u,g,o}, isDir): string` (comma-joined u,g,o);
wrappers `Fs.chgrp(group, paths, cb(ok))`, `Fs.chmodTree(dir, filesSym, dirsSym, cb(changed, skipped))`,
`Fs.groups(cb(list))`, `Fs.umask(cb(int))`.

- [ ] **Step 1: Update/add checks** in `selftest.qml`: change the existing access/withAccess expectations to title case
  ("Read and Write", "Read-Only", "Create and Delete Files", "Access Files", "List Files Only") and add:

```js
        // ---- properties redesign rules ----
        check("levels: owner has no None", Fs.levelsFor("u", false), ["Read-Only", "Read and Write"]);
        check("levels: others", Fs.levelsFor("o", true), ["None", "List Files Only", "Access Files", "Create and Delete Files"]);
        check("umask 002", Fs.umaskLevels(0o002), { files: { u: "Read and Write", g: "Read and Write", o: "Read-Only" },
              folders: { u: "Create and Delete Files", g: "Create and Delete Files", o: "Access Files" } });
        check("umask 022", Fs.umaskLevels(0o022), { files: { u: "Read and Write", g: "Read-Only", o: "Read-Only" },
              folders: { u: "Create and Delete Files", g: "Access Files", o: "Access Files" } });
        check("symbolic: file read-only", Fs.symbolic("g", "Read-Only", false), "g+r,g-w");
        check("symbolic: file rw", Fs.symbolic("g", "Read and Write", false), "g+rw");
        check("symbolic: file none", Fs.symbolic("o", "None", false), "o-rw");
        check("symbolic: dir none", Fs.symbolic("o", "None", true), "o-rwx");
        check("symbolic: dir list", Fs.symbolic("o", "List Files Only", true), "o+r,o-wx");
        check("symbolic: dir access", Fs.symbolic("u", "Access Files", true), "u+rx,u-w");
        check("symbolic: dir all", Fs.symbolic("g", "Create and Delete Files", true), "g+rwx");
        check("symbolicAll", Fs.symbolicAll({ u: "Read and Write", g: "Read-Only", o: "None" }, false), "u+rw,g+r,g-w,o-rw");
```

- [ ] **Step 2: Run** selftest — Expected: FAIL (old texts / missing functions).
- [ ] **Step 3: Implement** in `Fs.qml`; also update every place that compares level texts (`PropsPermissions.qml`,
  `Properties.qml` permsState users) — `grep -n '"Read' …/*.qml`.
- [ ] **Step 4: Run** selftest — Expected: `selftest: 0 failures`.
- [ ] **Step 5: Commit** — `"Himeko Files: permission rules for the redesign (title-case levels, umask, symbolic modes)"`; push.

---

### Task 3: Rows, groups, popover, page stack and the main page

**Files:** Create `PropRow.qml`, `PropGroup.qml`; Modify `Properties.qml`, `PropsOpenWith.qml`, `PropsDetails.qml`,
`Browser.qml`

**Interfaces:**
- Produces: `PropRow { property string kind: "property" | "nav" | "dropdown" | "switch" | "button"; property string
  title; property string value; property string icon /* right icon button for "property" */; property bool checked
  /* switch */; property bool enabled; signal clicked(); signal iconClicked() }` (property rows: dim 12 px title above a
  13–14 px plain-text value; nav: title left, value + `chevron_right` right; dropdown: value + `expand_more`, no chevron
  when not enabled; button: centred bold title).
  `PropGroup { property string title; default property alias rows: …column.data }` (rounded clip, 2 px gaps).
  `Properties.page: string` ("" = main), `Properties.goPage(name)`, `Properties.back()` (the Esc function: popover →
  page → card), `Properties.openChoice(anchor: Item, key: string, choices: var, current: string, searchable: bool,
  onPick: function)`, `Properties.popoverKey: string`, `Properties.pick(choice)`.
  IPC: `propsPage(name)`, `propsBack()`, `propsOpen(key)` (opens a dropdown by key: `access:u|g|o`,
  `access:files:u`…, `group`, `enclosed:files:u`…), `propsPick(choice)`; `propsState()` drops `tab`/`tabs`, adds
  `page`, `pages` (nav rows on the main page), `popover` (open key or "").

- [ ] **Step 1: Build `PropRow.qml` and `PropGroup.qml`** per the Interfaces and Global Constraints (row hover only when
  clickable; values `textFormat: Text.PlainText`, elide middle for paths).
- [ ] **Step 2: Restructure `Properties.qml`.** Keep the data/logic half (load, counting, perms, apps, meta, rename,
  setPerm, setDefault). Replace the view: header bar (main: Open + close; sub-pages: back chevron, centred bold title,
  close); page area = one Loader per page with the slide (x 40 → 0 + fade when going forward, reversed going back);
  card height = header + current page's implicit height, ≤ 86 %, page area scrolls (Flickable) when taller.
  Main page: hero (Thumb 96 radius 18; pencil badge = small round IconButton at the thumb's bottom-right when
  `canRename` → name swaps to `RenameField`; name 18 px bold; subtitle per the spec with a small spinning
  `progress_activity` icon while `counting`; third line free space for folders), groups "where" (Parent Folder with
  `folder_open` icon → `go(parent)`; Link Target), "when" (Size for files with exact bytes, Modified, Created), "more"
  (nav rows Permissions / Open With / Details per the spec's conditions; Details title "<Kind> Details").
  Remove the tab chips, `Fs.propsTab`, Ctrl+Tab; add Esc → `back()`, Alt+Left/Backspace (not renaming) → back a page.
- [ ] **Step 3: Popover.** One `Glass` popover item in `Properties` (radius 12, rows 36 px with a `check` on the current
  choice, optional search `TextInput` filtering case-insensitively, max 8 rows then scroll), positioned under the
  anchor's value, flipped above when it would leave the window, clamped horizontally; click outside closes it.
- [ ] **Step 4: Open With and Details pages** in the boxed style (Open With: a row per app with icon, check on the
  default, click → `setDefault`; Details: property rows, values selectable). Wire IPC from the Interfaces.
- [ ] **Step 5: Check visually** (samples; `HF_ANIMATE=0 SIZE="1300 900"`): `props photo.png` (main), `props sub`
  (spinner then "3 items, totalling 11 B" + free space), `props "photo.png|notes.txt|sub"`, `propsPage "Open With"`,
  `props song.mp3` + `propsPage Details`; Trash item: no Permissions/Open With rows, no pencil. Compare with the
  recording frames (`scratchpad/rec/z4.png`).
- [ ] **Step 6: Check back navigation**: `props song.mp3`, `propsPage Details`, `propsBack` → `page` ""; `propsBack` →
  `open` false. (Popover placement and the full Esc order are checked in Task 4 Step 6, once dropdowns exist.)
- [ ] **Step 7: Run the suite; commit** — `"Himeko Files: Properties in the GNOME Files layout (hero, boxed rows, pages)"`; push.

---

### Task 4: Permissions page

**Files:** Rewrite `PropsPermissions.qml`; Modify `Properties.qml` (group data + `setGroup`), `Browser.qml` (`propsGroup`)

**Interfaces:**
- Consumes: Task 2 rules/wrappers, Task 3 rows/popover.
- Produces: `Properties.groups: var` (from `Fs.groups`, loaded when the page opens), `Properties.setGroup(name)` (chgrp all
  items, refresh `info`; failure toasts), `propsState().perms` gains `group` and `canGroup`; IPC `propsGroup(name)`.

- [ ] **Step 1: Build the page** per the spec: Owner group (Owner "name (You)", Access dropdown key `access:u`), Group
  group (Group dropdown key `group`, searchable, only when you own every item, else a property row; Access `access:g`),
  "Other Users" (Access `access:o`), files: switch row "Allow Executing File as Program", one folder you own: button row
  "Change Permissions for Enclosed Files…" → `goPage("Enclosed")`; both kinds: rows "Files"/"Folders" under each
  section (keys `access:files:u` …); read-only rows + note as before. Choices come from `Fs.levelsFor(who, isDir)`.
- [ ] **Step 2: Check**: scratch `perm.txt` (644): `props perm.txt`, `propsPage Permissions`, capture; `propsOpen
  access:o` capture (popover with check on Read-Only); `propsPick None` → `stat -c %a` = 640; `propsSet exec on` → 750.
- [ ] **Step 3: Group**: `propsOpen group` capture (search field, your groups); `propsGroup <another group of yours, e.g.
  docker>` → `stat -c %G perm.txt` = that group; `propsState().perms.group` matches.
- [ ] **Step 4: Review-focus — group you can't change**: `/etc/hostname` → `canGroup` false, no dropdown chevron (capture);
  `propsGroup docker` leaves `stat -c %G /etc/hostname` = root.
- [ ] **Step 5: Review-focus — both kinds**: `props "perm.txt|sub"` → Files/Folders rows, no Enclosed row (capture);
  `propsSet files:o Read-Only` changes perm.txt only.
- [ ] **Step 6: Review-focus — popover placement and Esc order** (`SIZE="500 900"`): `props perm.txt`, `propsPage
  Permissions`, `propsOpen access:o` → capture: popover fully inside the window; `propsBack` → `popover` "" and `page`
  "Permissions"; `propsBack` → page ""; `propsBack` → closed.
- [ ] **Step 7: Run the suite; commit** — `"Himeko Files: Properties permissions page with group change"`; push.

---

### Task 5: Enclosed page

**Files:** Create `PropsEnclosed.qml`; Modify `Properties.qml` (enclosed state + apply), `Browser.qml` (IPC)

**Interfaces:**
- Consumes: `Fs.umaskLevels`, `Fs.umask`, `Fs.symbolicAll`, `Fs.chmodTree`, `Fs.levelsFor`.
- Produces: `Properties.enclosed: var` (`{ files: {u,g,o}, folders: {u,g,o} }`, set from `umaskLevels` each time the page
  opens), `Properties.applyEnclosed()` (runs `chmodTree(folder, symbolicAll(files,false), symbolicAll(folders,true))`;
  `enclosedBusy` while running; toast "Changed permissions of N items" + ", M skipped" when M > 0; then back to the
  Permissions page; keeps running and toasts even if the card was closed). IPC `propsEnclosed(json: string)` (merges
  levels), `propsEnclosedApply()`; `propsState()` gains `enclosed` and `enclosedBusy`.

- [ ] **Step 1: Build the page**: header Cancel (pill, `back()` without changes) / "Change Permissions for Enclosed Files"
  / Change (primary pill, spinner + disabled while busy); sections Owner/Group/Others each with Files and Folders
  dropdown rows (keys `enclosed:files:u` …).
- [ ] **Step 2: Check start values**: `props sub` (scratch, yours), `propsPage Enclosed` → `propsState().enclosed` equals
  the umask 002 levels from the spec; capture and compare with `scratchpad/rec/z28.png`.
- [ ] **Step 3: Check apply**: scratch tree `$S/tree` (files 600, an executable 700, a subfolder 700, a symlink to
  `$SP/outside` 600): `props tree`, `propsPage Enclosed`, `propsEnclosed '{"files":{"o":"None"},"folders":{"o":"None"}}'`,
  `propsEnclosedApply` → files 660, executable 770, subfolder 770, `outside` still 600, toast text in the log/capture,
  page back to Permissions.
- [ ] **Step 4: Review-focus — close mid-run**: a tree of 20,000 files; `propsEnclosedApply` then `props ""` at once →
  after 3 s every file has the new mode and no `chmod`/`find` from ops.sh is left.
- [ ] **Step 5: Run the suite; commit** — `"Himeko Files: change permissions for enclosed files"`; push.

---

### Task 6: Finish

- [ ] **Step 1**: Narrow (`SIZE="500 900"`) captures of the main page and Permissions page; animations-off capture.
- [ ] **Step 2**: Perf on `~/Pictures/Wallpapers`, card closed, twice — idle ≤ 0.5 %, RSS within noise of 253–254 MB.
- [ ] **Step 3**: README Properties bullet: add "group, and permissions for everything inside a folder".
- [ ] **Step 4**: `done.sh`; suite; commit `"Himeko Files: properties redesign finished"` with the perf lines; push.
