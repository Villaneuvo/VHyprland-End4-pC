# Himeko Files Places Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recent, Starred and pinned folders (GTK bookmarks) in a GNOME Files 47 sidebar.

**Architecture:** A small Python helper (`places.py`, stdlib + GLib via `gi`) owns every read and write of the three
files (GTK's `recently-used.xbel` and `bookmarks`, our `starred`), with atomic writes that keep mode and symlinks;
`ops.sh` dispatches to it. `Fs` watches `bookmarks` and `starred` with `FileView` and exposes them; `Tab` learns two
virtual locations, `recent:` and `starred:`, whose items come from `places.py` instead of `FolderListModel`.

**Tech Stack:** Quickshell (QML, Qt 6), Python 3 + `gi` (GLib), bash, gio.

**Spec:** `docs/superpowers/specs/2026-10-21-himeko-files-places-design.md`

## Global Constraints

- App code live in `~/.config/hypr/custom/himeko-files/`; `cd ~/VHyprland-End4-pC && ./sync.sh` copies it (add
  `places.py` to `manifest.txt` if the folder isn't listed whole). Commit on `main`, push per task, **no
  Co-Authored-By / AI attribution**.
- Files: recent = `$HF_RECENT` or `~/.local/share/recently-used.xbel`; bookmarks = `${XDG_CONFIG_HOME:-~/.config}/gtk-3.0/bookmarks`;
  starred = `$HF_STARRED` or `~/.local/state/himeko-files/starred` (one absolute path per line).
- Every write: read, change, write a temp file in the real target's folder (`os.path.realpath`), copy the old mode,
  `os.replace`. Never `GLib.BookmarkFile.to_file` (it would reset the 600 mode). Unknown bookmark lines kept in place.
- URIs via `GLib.filename_to_uri` / `GLib.filename_from_uri` (exactly what GTK writes).
- Recent: `file://` entries that exist, newest first by modified (else visited), at most 300; our opens are added with
  app "Himeko Files", exec `himeko-files %u`.
- No new timers; watches only (`FileView { watchChanges: true }`), recent watched only while `recent:` is shown.
- Sidebar order: Home, Recent (`schedule`), Starred (`star`), Network, Trash; separator; pins; Devices. Desktop is no
  longer fixed. XDG pin icons: Documents `description`, Downloads `download`, Music `music_note`, Pictures `image`,
  Videos `movie`, Desktop `desktop_windows`; others `folder`.
- Copy: "Pin to Sidebar", "Unpin from Sidebar", "Star", "Unstar", "Remove from Recent", "Open Item Location",
  "Rename…", "Move Up", "Move Down", "Unpin", "Open in New Tab", "This folder isn't available", "Opened <date>",
  empty states "Files you open will show here" / "Star files and folders to find them here", toast "Pinned “<name>”".
- File-derived text is `textFormat: Text.PlainText`. Tests on the headless output only; app tests run with
  `HF_ENV="XDG_CONFIG_HOME=<scratch>/cfg HF_RECENT=<scratch>/recent.xbel HF_STARRED=<scratch>/starred"` so the real
  files are never touched (compare `sha256sum` of the real three files before/after each visual task).
- Suite: `~/.config/hypr/custom/himeko-files/ops.sh selftest && qs -p ~/.config/hypr/custom/himeko-files/selftest.qml 2>&1 | grep -q 'selftest: 0 failures'`

## Review Focus

- **Another program writes the same file at the same time** (a GTK app adding to recent while we remove): the file
  stays valid for GLib and the other app's entry survives unless it was the one removed. Pinned in Task 1 Step 1.
- **Bookmarks file oddities** (sftp/smb lines, labels with spaces, non-ASCII and `#`/`%` in paths, no trailing
  newline, missing file): preserved or handled. Pinned in Task 1 Step 1.
- **Odd folder names in the UI** (`Proj #1 % ✨`): pin, star, navigate, recent all work and show literally. Pinned in
  Task 4 Step 4 and Task 5 Step 3.
- **A pin whose folder disappears and comes back** (unmounted drive): dimmed with the toast, undimmed when back
  (device change re-check). Pinned in Task 4 Step 5.
- **Changes from elsewhere while open** (pin written by another process, star from another window): show within a
  second through the watches. Pinned in Task 4 Step 6 and Task 5 Step 4.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `…/places.py` | recent / starred / bookmarks read and write; `moved` (rename follow) | Create |
| `…/ops.sh` | dispatch `recent`, `starred`, `bookmarks`, `placesmoved` to places.py; selftest | Modify |
| `…/Fs.qml` | file paths, watches, `bookmarks`, `starred`, `parseBookmarks`, `pinIcon`, wrappers, recent add on open, move hooks | Modify |
| `…/Tab.qml` | virtual locations `recent:` / `starred:` | Modify |
| `…/Sidebar.qml` | GNOME 47 order, pins, dim, row menu signal, inline rename | Modify |
| `…/Browser.qml` | menus (pin, star, recent), Ctrl+D, breadcrumb/title for virtual, empty states, IPC | Modify |
| `…/ItemTile.qml`, `…/DetailsList.qml` | star badge, "Opened …", Location column | Modify |
| `…/Properties.qml` | star button in the header | Modify |
| `…/selftest.qml` | rules | Modify |

(`…` = `~/.config/hypr/custom/himeko-files`)

---

### Task 1: places.py and its ops.sh commands

**Interfaces — Produces** (all through `ops.sh`, output TAB-separated, one item per line):
- `ops.sh recent list [MAX=300]` → `path  isDir(1|0)  size  mtime(epoch)  used(epoch)`;
  `ops.sh recent add PATH`; `ops.sh recent remove PATH`.
- `ops.sh starred list` → `path  isDir  size  mtime` (existing only); `ops.sh starred add PATH...`;
  `ops.sh starred remove PATH...`.
- `ops.sh bookmarks pin PATH [LABEL]`, `unpin PATH`, `rename PATH LABEL` (empty LABEL = no label),
  `move PATH -1|1`.
- `ops.sh placesmoved OLD NEW` → updates starred (the path and everything under it), bookmarks (same), recent
  (`move_item` for the path and entries under it).
- Exit 1 with a message on stderr when an argument is invalid; 0 otherwise (pinning twice is a no-op, 0).

- [ ] **Step 1: Write failing selftest checks** (in `ops.sh selftest`, before `exit $fail`; fixtures in `$t`,
  env overrides only):

```bash
    # ---- places: recent ----
    export HF_RECENT=$t/recent.xbel HF_STARRED=$t/state/starred XDG_CONFIG_HOME=$t/cfg
    mkdir -p "$t/pl/Proj #1 % ✨" "$t/pl/b"; : >"$t/pl/a.txt"; : >"$t/pl/b/c.txt"
    python3 -I - "$t" <<'PY'
import sys
from gi.repository import GLib
t=sys.argv[1]; bf=GLib.BookmarkFile()
def add(p, mod):
    u=GLib.filename_to_uri(p, None); bf.add_application(u, "test", "test %u"); bf.set_mime_type(u, "text/plain")
    bf.set_modified_date_time(u, GLib.DateTime.new_from_unix_utc(mod))
add(t+"/pl/a.txt", 100); add(t+"/pl/b/c.txt", 300); add(t+"/pl/gone.txt", 400)
bf.add_application("https://example.com/x", "test", "test %u")
open(t+"/recent.xbel","w").write(bf.to_data()[0] if isinstance(bf.to_data(), tuple) else bf.to_data())
PY
    chmod 600 "$t/recent.xbel"
    check "recent order, skips missing and non-file" "$("$me" recent list | cut -f1 | sed "s|$t/pl/||" | tr '\n' ' ')" "b/c.txt a.txt "
    check "recent cap" "$("$me" recent list 1 | wc -l)" "1"
    "$me" recent add "$t/pl/Proj #1 % ✨"
    check "recent add goes first" "$("$me" recent list | head -1 | cut -f1)" "$t/pl/Proj #1 % ✨"
    "$me" recent remove "$t/pl/a.txt"
    check "recent remove" "$("$me" recent list | grep -c 'a.txt')" "0"
    check "recent keeps other entries" "$(grep -c 'example.com' "$t/recent.xbel")" "1"
    check "recent keeps mode" "$(stat -c %a "$t/recent.xbel")" "600"
    # a GLib writer racing ours: the file stays loadable and its entry survives
    ( for i in $(seq 20); do python3 -I -c "
from gi.repository import GLib; import sys
bf=GLib.BookmarkFile(); bf.load_from_file(sys.argv[1]); bf.add_application('file:///race/$i','r','r %u')
d=bf.to_data(); open(sys.argv[1]+'.tmp','w').write(d[0] if isinstance(d,tuple) else d)
import os; os.replace(sys.argv[1]+'.tmp', sys.argv[1])" "$t/recent.xbel"; done ) &
    for i in $(seq 20); do "$me" recent add "$t/pl/b/c.txt"; done; wait
    check "recent file valid after a race" "$(python3 -I -c "from gi.repository import GLib; import sys; b=GLib.BookmarkFile(); b.load_from_file(sys.argv[1]); print('ok')" "$t/recent.xbel")" "ok"
    # ---- places: starred ----
    "$me" starred add "$t/pl/a.txt" "$t/pl/b" "$t/pl/a.txt"
    check "starred no duplicates" "$(sort "$t/state/starred" | uniq -d | wc -l)" "0"
    "$me" starred add "$t/pl/missing"
    check "starred list skips missing" "$("$me" starred list | cut -f1 | sed "s|$t/pl/||" | sort | tr '\n' ' ')" "a.txt b "
    "$me" starred remove "$t/pl/a.txt"
    check "starred remove" "$("$me" starred list | grep -c 'a.txt')" "0"
    # ---- places: bookmarks ----
    B=$t/cfg/gtk-3.0/bookmarks
    "$me" bookmarks pin "$t/pl/b"
    check "bookmarks file created" "$(cat "$B")" "$(python3 -I -c "from gi.repository import GLib; import sys; print(GLib.filename_to_uri(sys.argv[1], None))" "$t/pl/b")"
    printf 'sftp://host/srv Server\n%s My B\n' "$(cat "$B")" | head -c -1 >"$B"; chmod 640 "$B"   # no trailing newline
    "$me" bookmarks pin "$t/pl/Proj #1 % ✨" "Projects ✨"
    "$me" bookmarks pin "$t/pl/b"
    check "bookmarks pin keeps others, no dup" "$(cut -d' ' -f2- "$B" | tr '\n' '|')" "Server|My B|Projects ✨|"
    check "bookmarks keeps mode" "$(stat -c %a "$B")" "640"
    "$me" bookmarks move "$t/pl/Proj #1 % ✨" -1
    check "bookmarks move up" "$(cut -d' ' -f2- "$B" | tr '\n' '|')" "Server|Projects ✨|My B|"
    "$me" bookmarks rename "$t/pl/b" ""
    check "bookmarks rename to none" "$(sed -n 3p "$B" | grep -c ' ')" "0"
    "$me" bookmarks unpin "$t/pl/Proj #1 % ✨"
    check "bookmarks unpin" "$(wc -l <"$B")" "2"
    mv "$B" "$t/cfg/real-bookmarks"; ln -s ../real-bookmarks "$B"; "$me" bookmarks pin "$t/pl"   # dotfiles-style symlink
    check "bookmarks symlink kept" "$(test -L "$B" && echo link)" "link"
    check "bookmarks written through the link" "$(grep -c "pl$" "$t/cfg/real-bookmarks")" "1"
    # ---- places: moved ----
    "$me" starred add "$t/pl/b/c.txt"; "$me" bookmarks pin "$t/pl/b" B2 2>/dev/null
    mv "$t/pl/b" "$t/pl/b2"; "$me" placesmoved "$t/pl/b" "$t/pl/b2"
    check "moved: starred child follows" "$(grep -c "^$t/pl/b2/c.txt$" "$t/state/starred")" "1"
    check "moved: bookmark follows" "$(grep -c 'pl/b2' "$B")" "1"
    check "moved: recent follows" "$("$me" recent list | grep -c 'pl/b2/c.txt')" "1"
    # ---- speed: 1,000 entries ----
    cp "$HOME/.local/share/recently-used.xbel" "$t/big.xbel" 2>/dev/null && { s=$(date +%s%N); HF_RECENT=$t/big.xbel "$me" recent list >/dev/null; check "recent list of the real history < 300 ms" "$(( ($(date +%s%N)-s)/1000000 < 300 ))" "1"; }
    unset HF_RECENT HF_STARRED XDG_CONFIG_HOME
```

- [ ] **Step 2: Run** selftest — Expected: the new checks FAIL (usage).
- [ ] **Step 3: Implement `places.py`** (argv: `recent|starred|bookmarks|moved …`) and the `ops.sh` dispatch
  (`recent|starred|bookmarks) exec python3 -I "$(dirname "$0")/places.py" "$cmd" "$@"`; `placesmoved` → `moved`).
  One `atomic_write(path, text)` helper per the Global Constraints. Recent via `GLib.BookmarkFile` (`load_from_data`
  of the file text, `to_data`), mime for `add` from `gio info -a standard::content-type`.
- [ ] **Step 4: Run** selftest — Expected: all `ok`.
- [ ] **Step 5: Commit** — `"Himeko Files: places helper (recent, starred, GTK bookmarks)"`; push.

---

### Task 2: Fs: places state and rules

**Interfaces — Produces:** `Fs.recentPath: "recent:"`, `Fs.starredPath: "starred:"`; `Fs.bookmarks: var`
(`[{ uri, path /* "" for non-file */, label, name /* label or basename */ }]`, from a watched `FileView` on the
bookmarks file), `Fs.pins: var` (file entries only, in order, plus `exists: bool` filled by `checkPins()`),
`Fs.starred: var` (path → true, from a watched `FileView` on the starred file), `Fs.isStarred(path): bool`;
`Fs.parseBookmarks(text): var`, `Fs.pinIcon(path, dirs): string` (pure: `dirs` is `Fs.dirs`), `Fs.openedText(date): string` ("Opened " + `Fs.date`);
wrappers `Fs.recentList(cb(items))`, `Fs.starredList(cb(items))` (items like Tab's, plus `used: Date` for recent),
`Fs.recentAdd(path)`, `Fs.recentRemove(path, cb)`, `Fs.setStarred(paths, on)`, `Fs.pin(path)`, `Fs.unpin(path)`,
`Fs.renamePin(path, label)`, `Fs.movePin(path, d)`, `Fs.placesMoved(old, new)`, `Fs.checkPins()` (run on bookmarks
change and when `devices` changes).

- [ ] **Step 1: Write failing checks** in `selftest.qml`:

```js
        // ---- places rules ----
        const bm = Fs.parseBookmarks("file:///home/u/Documents\nsftp://host/srv Server\nfile:///home/u/Proj%20%231%20%25%20%E2%9C%A8 Projects ✨\n\n");
        check("bookmarks: count", bm.length, 3);
        check("bookmarks: plain", [bm[0].path, bm[0].label, bm[0].name], ["/home/u/Documents", "", "Documents"]);
        check("bookmarks: other scheme kept, no path", [bm[1].uri, bm[1].path, bm[1].label], ["sftp://host/srv", "", "Server"]);
        check("bookmarks: decoded path and label", [bm[2].path, bm[2].name], ["/home/u/Proj #1 % ✨", "Projects ✨"]);
        check("pinIcon: xdg", Fs.pinIcon("/h/Dl", { download: "/h/Dl", desktop: "/h/Desk" }), "download");
        check("pinIcon: desktop", Fs.pinIcon("/h/Desk", { download: "/h/Dl", desktop: "/h/Desk" }), "desktop_windows");
        check("pinIcon: other", Fs.pinIcon("/tmp/x", { download: "/h/Dl" }), "folder");
        check("openedText", Fs.openedText(new Date(Date.now() - 30000)), "Opened Just now");
```

- [ ] **Step 2: Run** selftest — Expected: FAIL (`parseBookmarks` not a function).
- [ ] **Step 3: Implement** in `Fs.qml` (watches via `FileView { path; watchChanges: true; onFileChanged: reload() }`;
  missing files = empty lists; `Fs.open`/`openIn`/`launchApp` also call `recentAdd`; `doPaste` with mode `move` calls
  `placesMoved(src, made[i])` per item; `rename` calls `placesMoved(old, target)`).
- [ ] **Step 4: Run** selftest — Expected: `selftest: 0 failures`.
- [ ] **Step 5: Commit** — `"Himeko Files: places state, watches and rules"`; push.

---

### Task 3: Recent and Starred as locations

**Files:** Modify `Tab.qml`, `Browser.qml`, `ItemTile.qml`, `DetailsList.qml`

**Interfaces:** `Tab.place: string` ("recent" | "starred" | ""), `Tab.virtual: bool`; `go("recent:")` /
`go("starred:")` work everywhere `go` works (IPC `go` included). IPC (test hooks): `open(names)` (select by name, then
`openSelection`), `recentRemove(name)` (the same function as the menu entry, on the item with that name).

- [ ] **Step 1: Tab.** `FolderListModel.folder` is "" when virtual; `reload()` for virtual calls `Fs.recentList` /
  `Fs.starredList` (answers for a place we left dropped) and keeps folder counting for the folders in the list;
  `name` = "Recent" / "Starred"; `goUp` does nothing when virtual; while `recent:` is shown a `FileView` watch on the
  recent file reloads it.
- [ ] **Step 2: Browser.** Breadcrumb: one crumb with the place's icon; header title from `tab.name`; background menu
  hides New Folder, Paste, Compress, Open Terminal; item menu adds **Open Item Location** (go to parent, select the
  item) in both, **Remove from Recent** in Recent; empty states with the place icon and the spec's text; `activate`
  of a file records it (through `Fs.open`).
- [ ] **Step 3: Tiles and details.** Recent tiles' second line: `Fs.openedText(item.used)` instead of the date;
  details view swaps Kind for **Location** (parent, `~`-shortened) when `tab.virtual`.
- [ ] **Step 4: Check** (scratch env; `HF_ENV` also sets `BROWSER=true` so opened files don't pop up apps — or use
  text samples opened with `XDG_CONFIG_HOME` mimeapps pointing `text/plain` to `true.desktop`): IPC `open notes.txt`,
  `open data.json`, `open doc.pdf` (1 s apart), then `go recent:` → those three first, newest first, "Opened Just
  now"; capture icons and details (Location column); `go starred:` → empty state capture; `recentRemove data.json` →
  gone after the reload. Real files' checksums unchanged.
- [ ] **Step 5: Run the suite; commit** — `"Himeko Files: Recent and Starred locations"`; push.

---

### Task 4: Sidebar and pinning

**Files:** Modify `Sidebar.qml`, `Browser.qml`

**Interfaces:** `Sidebar.pinMenu(path: string, x: real, y: real)` signal (Browser shows the row menu);
`Sidebar.renamingPin: string` (path being renamed inline; Enter → `Fs.renamePin`, Esc cancels). IPC:
`pin(name)` (selected/named folder, else current), `unpin(name)`, `pinRename(path, label)`, `pinMove(path, d)`.

- [ ] **Step 1: Sidebar** per the spec order; pins from `Fs.pins` (icon `Fs.pinIcon`, label `name`, dim when
  `!exists`; click on a missing pin → toast "This folder isn't available"); right-click → `pinMenu`; `activePlace`
  also matches pins and `recent:`/`starred:`; rail shows icons only.
- [ ] **Step 2: Browser:** row menu (Open in New Tab, Rename…, Move Up, Move Down, Unpin); item menu Pin/Unpin for a
  single folder; background menu Pin/Unpin for the current folder (not virtual); **Ctrl+D** toggles (selected folder,
  else current folder); toast "Pinned “<name>”".
- [ ] **Step 3: Check**: scratch bookmarks with the five XDG lines + an `sftp://` line; capture sidebar (1300 and
  500 px rail); `pin` a samples folder → appears last; `pinMove … -1`, `pinRename … "Work"` (capture inline rename by
  setting `renamingPin` over IPC before), `unpin` → file content matches each step; sftp line still there.
- [ ] **Step 4: Review focus — odd names**: `mkdir "$S/Proj #1 % ✨"`, pin it, click it (IPC `go` via the pin's
  path) → the folder opens; capture shows the label literally.
- [ ] **Step 5: Review focus — missing pin**: pin `$S/gone`, `rmdir` it, trigger `Fs.checkPins` (IPC `refreshPins`)
  → dimmed; recreate → undimmed after `refreshPins`.
- [ ] **Step 6: Review focus — outside change**: append a line to the scratch bookmarks file from the shell → the
  sidebar shows it within 1 s (no IPC call).
- [ ] **Step 7: Run the suite; commit** — `"Himeko Files: GNOME-style sidebar with pinned folders"`; push.

---

### Task 5: Stars

**Files:** Modify `Browser.qml`, `ItemTile.qml`, `DetailsList.qml`, `Properties.qml`

**Interfaces:** IPC `star(names)`, `unstar(names)`.

- [ ] **Step 1:** Item menu **Star** / **Unstar** (all selected; Unstar when all are starred); tile badge (filled
  `star`, 16 px, top-left, primary) and details badge after the name for `Fs.isStarred(path)`; Properties header:
  star `IconButton` at the left (outline `star` / filled primary), hidden for several items and in Trash.
- [ ] **Step 2: Check**: `star "photo.png|sub"` → badges (capture icons + details), `go starred:` lists both;
  Properties header star filled for photo.png (capture); `unstar photo.png` → badge gone, Starred list has `sub` only.
- [ ] **Step 3: Review focus — odd names**: star `Proj #1 % ✨`, rename it in the app (`propsRename` or `rename` IPC)
  → still starred under the new name; Starred view shows it literally.
- [ ] **Step 4: Review focus — other window**: append a path to the scratch starred file from the shell → its badge
  shows within 1 s.
- [ ] **Step 5: Run the suite; commit** — `"Himeko Files: stars"`; push.

---

### Task 6: Finish

- [ ] **Step 1**: Perf on `~/Pictures/Wallpapers`, twice — idle ≤ 0.5 %, RSS within noise of 254–255 MB; no new
  processes per minute from the app while idle (`ns_last_pid` delta over 60 s with the app on Wallpapers, compared with
  before Task 1's commit).
- [ ] **Step 2**: README Himeko Files bullet: `- **Places**: Recent (GTK's shared history), Starred, and pinned
  folders shared with GNOME Files and every GTK file dialog (Ctrl+D pins).`
- [ ] **Step 3**: `done.sh`; suite; real files' checksums unchanged since Task 1; commit
  `"Himeko Files: places finished"` with perf lines; push.
