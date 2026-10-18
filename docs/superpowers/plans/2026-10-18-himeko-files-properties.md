# Himeko Files Properties Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An Alt+Enter Properties card with General, Permissions, Open With and Details tabs.

**Architecture:** `ops.sh` gets the system side (`props`, streaming `dirsize`, `chmod`, sandboxed `meta`, `mimedefault`);
`Fs` wraps them and holds the pure rules (access levels ↔ mode bits, size/date text), unit-tested in `selftest.qml`.
`Properties.qml` is an on-demand overlay like `QuickLook.qml`, one file per heavier tab.

**Tech Stack:** Quickshell (QML, Qt 6), bash, bwrap, ImageMagick, ffprobe, poppler-utils, fontconfig, gio.

**Spec:** `docs/superpowers/specs/2026-10-18-himeko-files-properties-design.md`

## Global Constraints

- App code live in `~/.config/hypr/custom/himeko-files/`; `cd ~/VHyprland-End4-pC && ./sync.sh` copies it. Commit on
  `main`, push per task, **no Co-Authored-By / AI attribution**.
- No new dependencies. Metadata readers (`magick identify`, `ffprobe`, `pdfinfo`, `fc-scan`) run through ops.sh `sandbox()`.
- Properties lives in its own files, loaded on demand; nothing of it runs while closed; a running count is killed on close.
- All file-derived text (names, link targets, tags, EXIF) is `textFormat: Text.PlainText`.
- Motion: the Quick Look tokens; nothing animates when `Theme.animate` is false.
- Tests on the headless output only (`tools/himeko-files/capture.sh` …, then `tools/himeko-files/done.sh`), always
  `qs ipc --pid <test pid>`. Never `qs -p` a component file (it hangs).
- Suite: `~/.config/hypr/custom/himeko-files/ops.sh selftest && qs -p ~/.config/hypr/custom/himeko-files/selftest.qml 2>&1 | grep -q 'selftest: 0 failures'`

## Review Focus

- **Closing or reselecting during a long count** (`~`, `/usr`): the `find` is killed and no late total appears on another
  item. Pinned in Task 4 Step 6.
- **Permissions you can't change** (not your file, a symlink, mixed owners): read-only with the note, never a silent
  failed chmod; a chmod error toasts and the rows show the real mode. Pinned in Task 5 Step 5.
- **Files and folders selected together**: separate Files/Folders rows, each change touches only its class. Pinned in
  Task 5 Step 5.
- **The user's mimeapps file** (comments, no `[Default Applications]` section, existing line for the type): line
  replaced or added, everything else kept. Pinned in Task 2 Step 1.
- **Tags and names that look like markup** (`<b>` in a song title, odd file names): shown literally. Pinned in Task 6 Step 5.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `…/ops.sh` | `props`, `dirsize`, `chmod`, `meta`, `mimedefault`; selftest | Modify |
| `…/Fs.qml` | wrappers `props`, `dirSize` (streaming), `chmod`, `meta`, `setDefaultApp`; rules `accessOf`, `withAccess`, `isExec`, `withExec`, `shared`, `sizeText`, `fullDate` | Modify |
| `…/Properties.qml` | overlay card, header, tab chips, General tab, keys, motion | Create |
| `…/PropsPermissions.qml` | Permissions tab | Create |
| `…/PropsOpenWith.qml` | Open With tab | Create |
| `…/PropsDetails.qml` | Details tab | Create |
| `…/Browser.qml` | Alt+Enter, menu entries, `propsItems`, Loader, IPC | Modify |
| `…/selftest.qml` | rule checks | Modify |
| `README.md` | Properties bullet | Modify |

(`…` = `~/.config/hypr/custom/himeko-files`)

---

### Task 1: props, dirsize, chmod in ops.sh

**Files:** Modify `…/ops.sh` (header usage, new cases, selftest)

**Interfaces:**
- Produces (one output line per PATH, fields TAB-separated, in this order):
  `ops.sh props PATH...` → `mode(octal %a)  owner  group  mine(1|0)  size  atime  mtime  birth(0 = unknown)  type(file|dir|link)
  linktarget(""|target|"!broken")  mime  description  avail  total` (avail/total in bytes for dirs, empty otherwise).
  `ops.sh dirsize PATH...` → lines `items<TAB>bytes` every 5000 entries, then `done<TAB>items<TAB>bytes`; dirs count their
  contents (not themselves, hidden included, symlinks not followed, unreadable skipped), files count as one item; bytes
  = apparent sizes of regular files. `ops.sh chmod MODE PATH...` → chmod each non-symlink PATH; exit 1 if any failed.

- [ ] **Step 1: Write failing selftest checks** (before the final `exit $fail`):

```bash
    # ---- properties: props, dirsize, chmod ----
    mkdir -p "$t/p/d/.h"; printf 'abc' >"$t/p/f.txt"; printf '12345' >"$t/p/d/a"; printf '1' >"$t/p/d/.h/b"
    ln -s f.txt "$t/p/l"; ln -s nowhere "$t/p/dead"; chmod 640 "$t/p/f.txt"
    IFS=$'\t' read -r mode own grp mine size _ _ _ type tgt mime desc _ _ <<<"$("$me" props "$t/p/f.txt")"
    check "props mode" "$mode" "640"; check "props mine" "$mine" "1"; check "props size" "$size" "3"
    check "props type" "$type" "file"; check "props mime" "$mime" "text/plain"
    check "props link" "$("$me" props "$t/p/l" | cut -f9,10)" "link"$'\t'"f.txt"
    check "props broken link" "$("$me" props "$t/p/dead" | cut -f10)" "!broken"
    check "props dir free space" "$("$me" props "$t/p/d" | awk -F'\t' '{ print ($13 > 0 && $14 >= $13) }')" "1"
    check "props one line per path" "$("$me" props "$t/p/f.txt" "$t/p/d" | wc -l)" "2"
    check "dirsize folder" "$("$me" dirsize "$t/p/d" | tail -1)" "done"$'\t'"3"$'\t'"6"
    check "dirsize mixed" "$("$me" dirsize "$t/p/d" "$t/p/f.txt" | tail -1)" "done"$'\t'"4"$'\t'"9"
    "$me" chmod 4750 "$t/p/f.txt"; check "chmod" "$(stat -c %a "$t/p/f.txt")" "4750"
    "$me" chmod 600 "$t/p/l"; check "chmod skips symlinks" "$(stat -c %a "$t/p/f.txt")" "4750"
```

- [ ] **Step 2: Run** `…/ops.sh selftest` — Expected: new checks FAIL (usage), the rest ok.

- [ ] **Step 3: Implement.** `props`: `stat -c` for the fields (`%a %U %G %u %s %X %Y %W %F`), `mine` = `%u` equals
  `id -u`; type from `-L`/`-d`; link target `readlink`, `!broken` when `[ ! -e ]`; mime/description from one
  `gio info -a standard::content-type,standard::description`; dirs add `df -B1 --output=avail,size`. `dirsize`: per
  PATH, dirs `find PATH -mindepth 1 \( -type f -printf '%s\n' -o -printf '0\n' \) 2>/dev/null`, files `stat -c %s`, all
  into one `awk` that prints running totals every 5000 lines (`fflush()`) and the `done` line. `chmod`: skip `-L`.

- [ ] **Step 4: Run** `…/ops.sh selftest` — Expected: all `ok`.

- [ ] **Step 5: Commit** — `"Himeko Files: ops for properties (stat, live folder size, chmod)"`; push.

---

### Task 2: meta and mimedefault in ops.sh

**Files:** Modify `…/ops.sh`

**Interfaces:**
- Consumes: `sandbox()`, `inpath()`, `unsandbox()` (Previews).
- Produces: `ops.sh meta FILE KIND` → `Label<TAB>Value` lines (empty values omitted), KIND ∈ image/video/audio/pdf/font,
  readers inside `sandbox`. Labels exactly as the spec's Details table (Dimensions, Color, Bit depth, Camera, Taken,
  Exposure, Aperture, ISO, Focal length, Orientation | Duration, Title, Artist, Album, Year, Video, Audio, Bitrate |
  Pages, Title, Author, Subject, Creator, Producer, Page size, PDF version | Family, Style, Version, Foundry).
  `ops.sh mimedefault MIME DESKTOP_ID` → writes `MIME=DESKTOP_ID` under `[Default Applications]` of
  `$XDG_CONFIG_HOME/<lowercased XDG_CURRENT_DESKTOP>-mimeapps.list` if that file exists, else
  `$XDG_CONFIG_HOME/mimeapps.list` (`XDG_CONFIG_HOME` defaults to `~/.config`); prints the file it wrote.

- [ ] **Step 1: Write failing selftest checks:**

```bash
    # ---- properties: meta, mimedefault ----
    magick -size 320x200 xc:pink "$t/m.png"
    check "meta image" "$("$me" meta "$t/m.png" image | grep '^Dimensions')" "Dimensions"$'\t'"320 × 200"
    check "meta song title" "$("$me" meta "$t/song.mp3" audio | grep -c '^Duration')" "1"
    ffmpeg -loglevel error -y -f lavfi -i sine=duration=1 -metadata title='<b>Bold</b> & co' -metadata artist=Himeko "$t/tag.mp3"
    check "meta tags" "$("$me" meta "$t/tag.mp3" audio | grep -E '^(Title|Artist)' | tr '\n' '|')" "Title"$'\t''<b>Bold</b> & co|Artist'$'\t''Himeko|'
    check "meta pdf pages" "$("$me" meta "$t/two.pdf" pdf | grep '^Pages')" "Pages"$'\t'"2"
    check "meta font style" "$("$me" meta "$bold" font | grep '^Style')" "Style"$'\t'"Bold"
    c=$t/cfg; mkdir -p "$c"; printf '# mine\n[Added Associations]\nx/y=a.desktop;\n' >"$c/mimeapps.list"
    XDG_CONFIG_HOME=$c XDG_CURRENT_DESKTOP=Hyprland "$me" mimedefault image/png loupe.desktop >/dev/null
    check "mimedefault adds section" "$(grep -A1 '^\[Default Applications\]' "$c/mimeapps.list" | tail -1)" "image/png=loupe.desktop"
    check "mimedefault keeps the rest" "$(head -3 "$c/mimeapps.list" | tr '\n' '|')" "# mine|[Added Associations]|x/y=a.desktop;|"
    printf '# hypr\n[Default Applications]\nimage/png=old.desktop\nvideo/mp4=vlc.desktop\n' >"$c/hyprland-mimeapps.list"
    check "mimedefault picks desktop file" "$(XDG_CONFIG_HOME=$c XDG_CURRENT_DESKTOP=Hyprland "$me" mimedefault image/png loupe.desktop)" "$c/hyprland-mimeapps.list"
    check "mimedefault replaces" "$(tr '\n' '|' <"$c/hyprland-mimeapps.list")" "# hypr|[Default Applications]|image/png=loupe.desktop|video/mp4=vlc.desktop|"
```

(`$t/song.mp3`, `$t/two.pdf`, `$bold` come from earlier selftest blocks; keep this block after them.)

- [ ] **Step 2: Run** selftest — Expected: new checks FAIL.

- [ ] **Step 3: Implement.** `meta` per KIND inside `sandbox` (`magick identify -format` with `%w × %h`, `%[colorspace]`,
  `%z`, `%[EXIF:Make]` …; `ffprobe -v error -show_format -show_streams -of json` parsed with `jq` outside the sandbox;
  `pdfinfo`; `fc-scan --format`). Duration as `m:ss` (`h:mm:ss` from an hour). `mimedefault`: awk rewrite to a temp file
  then `mv` (replace the type's line inside `[Default Applications]`, else insert after the header, else append the
  section).

- [ ] **Step 4: Run** selftest — Expected: all `ok`.

- [ ] **Step 5: Commit** — `"Himeko Files: metadata readers (sandboxed) and default-app writer"`; push.

---

### Task 3: Rules in Fs

**Files:** Modify `…/Fs.qml`, `…/selftest.qml`

**Interfaces:**
- Produces: `Fs.accessOf(mode: int, who: "u"|"g"|"o", isDir: bool): string` — files `None` / `Read-only` /
  `Read and write` (x ignored); folders `None` / `List files only` / `Access files` / `Create and delete files`; any
  other combination `""` (shown as "Custom"). `Fs.levels(isDir): var` (the list in that order).
  `Fs.withAccess(mode, who, level, isDir): int` (touches only that class's rwx — files keep that class's x).
  `Fs.isExec(mode): bool` (any x), `Fs.withExec(mode, on): int` (on: x for each class that has r; off: clear all x).
  `Fs.shared(values: var)` → the value if all equal, else `"Mixed"`. `Fs.sizeText(bytes): string`. `Fs.fullDate(d): string`.
  Plus wrappers: `Fs.props(paths, cb(list))` (objects `{ mode:int, owner, group, mine:bool, size, atime:Date,
  mtime:Date, birth:Date|null, type, target, mime, description, avail, total }`), `Fs.dirSize(paths, cb(items, bytes,
  done)) → Process` (caller sets `running = false` to stop), `Fs.chmod(mode, paths, cb(ok))`, `Fs.meta(path, kind,
  cb(rows: [[label, value]]))`, `Fs.setDefaultApp(mime, id, cb(ok))`.

- [ ] **Step 1: Write failing checks** in `selftest.qml`:

```js
        // ---- properties rules ----
        check("access: file rw", Fs.accessOf(0o644, "u", false), "Read and write");
        check("access: file r", Fs.accessOf(0o644, "g", false), "Read-only");
        check("access: file none", Fs.accessOf(0o600, "o", false), "None");
        check("access: dir rwx", Fs.accessOf(0o755, "u", true), "Create and delete files");
        check("access: dir r-x", Fs.accessOf(0o755, "g", true), "Access files");
        check("access: dir r--", Fs.accessOf(0o744, "g", true), "List files only");
        check("access: dir custom", Fs.accessOf(0o730, "g", true), "");
        check("withAccess: file others none", Fs.withAccess(0o644, "o", "None", false), 0o640);
        check("withAccess: keeps setuid", Fs.withAccess(0o4755, "g", "List files only", true), 0o4745);
        check("withAccess: file keeps x", Fs.withAccess(0o755, "u", "Read-only", false), 0o555);
        check("exec: off", Fs.isExec(0o644), false);
        check("exec: on where readable", Fs.withExec(0o640, true), 0o750);
        check("exec: clear", Fs.withExec(0o755, false), 0o644);
        check("shared: same", Fs.shared(["a", "a"]), "a");
        check("shared: mixed", Fs.shared(["a", "b"]), "Mixed");
        check("sizeText", Fs.sizeText(2412345), "2.3 MB (2,412,345 bytes)");
        check("sizeText small", Fs.sizeText(512), "512 bytes");
        check("fullDate", Fs.fullDate(new Date(2026, 9, 18, 16, 30)), "Saturday, 18 October 2026, 16:30");
```

- [ ] **Step 2: Run** selftest — Expected: FAIL (`accessOf` not a function).

- [ ] **Step 3: Implement** the rules and the wrappers (`dirSize` uses a Process with a `SplitParser` on stdout; the
  wrappers parse the ops.sh lines from Tasks 1–2).

- [ ] **Step 4: Run** selftest — Expected: `selftest: 0 failures`.

- [ ] **Step 5: Commit** — `"Himeko Files: permission levels, size and date text for properties"`; push.

---

### Task 4: Properties card and General

**Files:** Create `…/Properties.qml`; Modify `…/Browser.qml`

**Interfaces:**
- Consumes: Task 3 wrappers/rules; `Fs.rename(path, name, cb)`; `tab.selectPath(path)`.
- Produces: `Browser.propsItems: var` (array, `null` = closed), `Browser.openProps(items)`, `Browser.closeProps()`.
  `Properties { required property var items; required property var tab; property Item backdrop; property bool shown;
  property string tabName; readonly property var tabs; property var info /* Fs.props list */; signals close(), faded(),
  go(string path), renamed(string path) }`. IPC: `props(names: string)` (select `a|b` by name, then `openProps`; `""`
  closes; `"."` = the current folder), `propsTab(name: string)`, `propsState(): string` → JSON `{ open, tab, tabs, name,
  size, counting, perms: { u, g, o, exec, editable }, apps, meta }` (fields of later tabs 0/""/false until they exist).

- [ ] **Step 1: Wire Browser.** Alt+Enter → `openProps(tab.selectedItems)` (nothing selected → nothing); F11 stays the
  info panel. Item menu "Properties" (hint "Alt+Enter") → `openProps(tab.selectedItems)`; background menu gets
  "Properties" → the current folder as an item (`{ name: tab.name, path: tab.path, isDir: true, suffix: "", size: 0,
  modified: <from props> }`). Loader + close fade exactly like Quick Look (`propsShown` during the fade); `go(path)` →
  `tab.go(path)` and close; `renamed(path)` → `tab.selectPath(path)` and the card follows the new path (Browser swaps `propsItems` to the item with
  that path once the listing has it). Any shown item leaving the listing otherwise → close, as Quick Look does.

- [ ] **Step 2: Build `Properties.qml`** — dim + Glass card (~560 px, height to content, ≤ 86 %); header (Thumb 48,
  name, type); tab chips (General, Permissions, Open With [one file], Details [one file with meta rows]) — the session
  remembers the last tab (a property on `Fs`); Esc closes, Ctrl+Tab/Ctrl+Shift+Tab switch tabs, all keys accepted.
  General rows per the spec table (`Fs.sizeText`, `Fs.fullDate`, `description (mime)`, link target, Location as a link
  → `go(parent)`, free space for folders, multi-item totals). The Name row is a `RenameField` for one item → `Fs.rename`.
  Folder/multi sizes from `Fs.dirSize`: row shows "Counting… N items, X" while running, "N items, totalling X" when done;
  the Process is stopped in `Component.onDestruction` and when `items` change; answers for old items dropped.

- [ ] **Step 3: Check visually** (samples folder from `tools/himeko-files/samples.sh`):
  `HF_ANIMATE=0 SIZE="1300 900" capture.sh <shots>/p3-general-file.png $S -- "props photo.png"`, then on the same pid
  `props sub`, `props "photo.png|notes.txt|sub"`, `props .` (each captured with `wincap.qml`). Expected: exact bytes,
  three full dates (Created if recorded), "PNG image (image/png)", folder "3 items, totalling …", multi
  "3 items (1 folder, 2 files)". Narrow: `SIZE="500 900"` `props photo.png`.

- [ ] **Step 4: Check rename**: IPC `propsRename(name: string)` calls the same function as Enter in the Name field.
  `cp $S/notes.txt $S/ren.txt`; `props ren.txt`; `propsRename ren2.txt` → `$S/ren2.txt` exists and `propsState().name`
  is `ren2.txt` (the card followed). Then `mv $S/ren2.txt $SP/` while open → card closes (left the listing, not our
  rename); move it back.

- [ ] **Step 5: Check nothing-selected and close**: `props ""`; `select ""` then the Alt+Enter path via `props
  nonexistent` → `"open":false`.

- [ ] **Step 6: Review-focus check — long count**: `go ~`, `props .`, after 0.5 s `propsState` shows `"counting":true`;
  `props ""`; after 0.5 s `pgrep -P <app pid> -f 'find '` and `pgrep -f "find $HOME -mindepth 1"` print nothing; then
  `props .` on `/usr` and immediately `props` on a file → final state shows the file's size, never `/usr`'s totals.

- [ ] **Step 7: Run the suite; commit** — `"Himeko Files: Properties card (Alt+Enter) with General"`; push.

---

### Task 5: Permissions

**Files:** Create `…/PropsPermissions.qml`; Modify `…/Properties.qml`

**Interfaces:**
- Consumes: `Fs.accessOf/levels/withAccess/isExec/withExec/shared/chmod/props`; `Properties.info`.
- Produces: `propsState().perms` filled: `{ u, g, o, exec, editable }` (`u/g/o` = level text, "Mixed" or "Custom";
  with files and folders together: `{ files: {u,g,o}, folders: {u,g,o}, exec, editable }`).

- [ ] **Step 1: Build the tab.** Owner/group names ("You" when `mine`). One row per class with a chip group of
  `Fs.levels(isDir)` (the current level filled; "Mixed"/"Custom" shows no chip filled plus a small label); files get the
  "Allow executing file as program" toggle (`Fs.isExec`, mixed → indeterminate look). Files+folders selection: a
  "Files" block and a "Folders" block. Choosing a chip: per item `Fs.withAccess(item.mode, …)`; items sharing a result
  go in one `Fs.chmod` call; afterwards `Fs.props` refreshes `info`. Not editable (any item not `mine`, or a symlink):
  chips disabled + "Only the owner can change these permissions". chmod failure → `Fs.failed(text)` toast + refresh.

- [ ] **Step 2: IPC test hook**: `propsSet(who: string, level: string)` (who `u|g|o|exec`, level text or `on/off`;
  with mixed kinds prefix `files:`/`folders:`) — calls the same function the chips call.

- [ ] **Step 3: Check**: copy `notes.txt` to `perm.txt` (mode 644); `props perm.txt`, `propsTab Permissions`,
  capture; `propsSet o None` → `stat -c %a perm.txt` = `640` and `propsState` perms.o = "None"; `propsSet exec on` →
  `750`; `propsSet exec off` → `640`.

- [ ] **Step 4: Check read-only**: `go /etc`, `props hostname`, `propsTab Permissions` → `"editable":false`, capture shows
  the note; `propsSet o None` leaves `stat -c %a /etc/hostname` unchanged.

- [ ] **Step 5: Review-focus checks**: back in samples, `props perm.txt|sub` → perms has `files` and `folders`;
  `propsSet files:o "Read-only"` changes `perm.txt` only (`sub` keeps its mode); a symlink (`ln -s perm.txt plink`)
  `props plink` → `"editable":false`.

- [ ] **Step 6: Run the suite; commit** — `"Himeko Files: Properties permissions"`; push.

---

### Task 6: Open With and Details

**Files:** Create `…/PropsOpenWith.qml`, `…/PropsDetails.qml`; Modify `…/Properties.qml`,
`tools/himeko-files/capture.sh` (`HF_ENV`: extra `NAME=value` words put before the app on its `env` line)

**Interfaces:**
- Consumes: `Fs.appsFor(path, cb(apps, mime))`, `Fs.setDefaultApp`, `Fs.meta`.
- Produces: `propsState().apps` (count) and `.meta` (row count); IPC `propsDefault(id: string)` → same as the row button.

- [ ] **Step 1: Open With tab**: the apps (icon, name, "Default" badge), a "Set as default" button on the others →
  `Fs.setDefaultApp(mime, id)` → toast `"<app name> is now the default for <description>"` (e.g. "Image Viewer is now the
  default for PNG image") and refresh.

- [ ] **Step 2: Details tab**: `Fs.meta(path, kind)` once per item (kind image/video/audio/pdf/font only); two-column
  label/value list, values selectable (`TextEdit { readOnly: true; textFormat: TextEdit.PlainText }`); the chip hides
  when there are no rows. Answers for an old item dropped.

- [ ] **Step 3: Check Open With without touching the user's real file**: launch the test app with
  `XDG_CONFIG_HOME=<scratch>/cfg` copied from `~/.config/*mimeapps.list` (`HF_ENV="XDG_CONFIG_HOME=<scratch>/cfg" capture.sh …`); `props photo.png`, `propsTab "Open With"`, capture; `propsDefault
  <another app id from the list>` → the scratch `hyprland-mimeapps.list` has `image/png=<id>`, the real
  `~/.config/hyprland-mimeapps.list` is unchanged (`sha256sum` before and after).

- [ ] **Step 4: Check Details**: `props photo.png` / `song.mp3` / `clip.mp4` / `doc.pdf` / `font.ttf`, `propsTab
  Details`, capture each. Expected rows per the spec table; `pack.zip` has no Details chip (`propsState().tabs`).

- [ ] **Step 5: Review-focus check — markup in tags**: `ffmpeg … -metadata title='<b>Bold</b> & co' $S/tag.mp3`;
  `props tag.mp3`, Details → the title reads literally in the capture.

- [ ] **Step 6: Run the suite; commit** — `"Himeko Files: Properties open-with and details"`; push.

---

### Task 7: Finish

**Files:** Modify `README.md`

- [ ] **Step 1: Animations off**: `HF_ANIMATE=0 … "props photo.png"` capture — card fully visible.
- [ ] **Step 2: Performance** (card closed) on `~/Pictures/Wallpapers`, `perf.sh 10` twice — Expected: idle ≤ 0.5 %, RSS
  within noise of Previews (251–252 MB).
- [ ] **Step 3: README** under Himeko Files: `- **Properties** (Alt+Enter): exact size and live folder totals, full dates,
  permissions you can change, the default app for the type, and photo/song/video/PDF/font details.`
- [ ] **Step 4**: `tools/himeko-files/done.sh`; suite; commit `"Himeko Files: properties finished (README, perf)"` with
  the perf lines; push.
