# Himeko Files Previews Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Real thumbnails from the system thumbnailers (sandboxed) and a Quick Look preview on Space.

**Architecture:** `ops.sh` learns which extensions have a thumbnailer (`thumbexts`) and runs every thumbnailer, ImageMagick,
ffmpeg and poppler inside `bwrap` (`thumb`, `page`, `pages`); `text` reads a capped, binary-checked prefix. `Fs` loads the
extension set at startup and remembers failures. Quick Look is an on-demand overlay (`QuickLook.qml` plus one file per
heavy body) that `Browser.qml` opens with Space; pure rules (`Fs.previewType`, `Fs.stepIndex`) are unit-tested.

**Tech Stack:** Quickshell (QML, Qt 6), QtMultimedia (ffmpeg backend), bash, bwrap, poppler-utils, ImageMagick, ffmpeg.

**Spec:** `docs/superpowers/specs/2026-10-18-himeko-files-previews-design.md`

## Global Constraints

- App code: live in `~/.config/hypr/custom/himeko-files/`; `cd ~/VHyprland-End4-pC && ./sync.sh` copies it to
  `home/.config/hypr/custom/himeko-files/`. Commit on `main`, push after each task, **no Co-Authored-By / AI attribution**.
- No new dependencies (`bwrap`, `pdftoppm`/`pdfinfo`, `ffmpegthumbnailer`, `magick`, QtMultimedia are installed).
- Quick Look lives in its own files, loaded on demand; nothing of it exists while closed.
- All file-derived text (names, file content, tags) is shown as plain text (`textFormat: Text.PlainText`).
- Thumbnail cache: `~/.cache/thumbnails/large/<md5 of URI>.png`, 256 px. Fail markers:
  `~/.cache/thumbnails/fail/himeko-files/<same name>`.
- Sandboxed output must be named `/tmp/gnome-desktop-out.png` inside the sandbox (Ubuntu AppArmor lets
  `papers-thumbnailer` write only `/tmp/gnome-desktop-*`).
- Motion uses Sub-project 1's tokens (`Anim { kind: … }`, `Theme.dur()`); nothing animates when `Theme.animate` is false.
- Tests run on the headless output only: `tools/himeko-files/capture.sh` …, then `tools/himeko-files/done.sh`. Always
  `qs ipc --pid <test pid>`. `HF_MUTE=1` (default in `capture.sh`) keeps tests silent.
- Suite (every task's final run):
  `~/.config/hypr/custom/himeko-files/ops.sh selftest && qs -p ~/.config/hypr/custom/himeko-files/selftest.qml 2>&1 | grep -q 'selftest: 0 failures'`

## Review Focus

- **Stepping fast through mixed files** (song → clip → text → PDF with Right held): only the current item plays, and a
  late answer for an earlier item (MIME, text, page) never shows on the current one. Pinned in Task 4 Step 6, Task 5 Step 6.
- **Broken or huge files** (random bytes named `.pdf`/`.mp4`, a 2 GB log): fallback card or capped text, window stays
  responsive. Pinned in Task 5 Step 6, Task 6 Step 5, Task 4 Step 6.
- **The previewed file disappears** (deleted/renamed while Quick Look is open): Quick Look closes. Pinned in Task 3 Step 7.
- **Odd names** (spaces, quotes, `<b>`, unicode): thumbnails still made (bwrap quoting), header shows the name literally.
  Pinned in Task 1 Step 1 and Task 3 Step 7.
- **Space with nothing focused / while typing**: nothing focused → nothing opens (Task 3 Step 7). Typing in rename,
  search and path fields can't be injected safely in tests: reviewer checks that Space is only handled by the view's
  `Keys.onPressed` (which those fields never reach).

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `…/ops.sh` | `thumbexts`, sandboxed `thumb` (+ fail markers), `page`, `pages`, `text`; selftest | Modify |
| `…/Fs.qml` | kinds lists, `thumbExts`, `canThumb`, failures, `requestThumb(path, kind)`, `appsFor` → MIME, `previewType`, `stepIndex` | Modify |
| `…/Theme.qml` | `mute` (HF_MUTE) | Modify |
| `…/Thumb.qml` | which items request thumbnails, crop vs fit, audio badge | Modify |
| `…/QuickLook.qml` | overlay, card, header, keys, motion, image/folder/info bodies | Create |
| `…/LookMedia.qml` | video + audio body with controls | Create |
| `…/LookPdf.qml` | PDF page body | Create |
| `…/LookText.qml` | text body | Create |
| `…/LookFont.qml` | font sample body | Create |
| `…/Browser.qml` | Space, `lookItem`, step, menu entry, Loader, IPC | Modify |
| `…/selftest.qml` | `previewType`, `stepIndex`, `canThumb` checks | Modify |
| `tools/himeko-files/samples.sh` | generates the sample folder used by visual checks | Create |
| `tools/himeko-files/capture.sh` | passes `HF_MUTE` (default 1) | Modify |
| `README.md` | Previews bullet | Modify |

(`…` = `~/.config/hypr/custom/himeko-files`)

---

### Task 1: Sandboxed thumbnails in ops.sh

**Files:** Modify `…/ops.sh` (header usage lines, `thumb)` case, new `thumbexts)` case, `selftest)` case)

**Interfaces:**
- Produces: `ops.sh thumbexts` → one lowercase extension per line (no dot), sorted, unique.
  `ops.sh thumb SRC DST SIZE KIND` (KIND = the app's kind: `image`, `video` or anything else) → exit 0 when DST written,
  1 on failure (and a fail marker exists afterwards).
  Env `HF_THUMBNAILERS` (colon-separated dirs, default `$HOME/.local/share/thumbnailers:/usr/share/thumbnailers`).
  Shell function `sandbox SRC CMD...` inside ops.sh, reused by Task 5: creates a host temp dir in global `sbdir`, runs
  CMD in bwrap with SRC at `/input.<ext>` and `$sbdir` at `/tmp` (CMD's stdout passes through); the caller reads
  `$sbdir/gnome-desktop-out.png` and removes `$sbdir`.

- [ ] **Step 1: Write the failing selftest checks** (append before `exit $fail` in `selftest)`; they build their own
  fixtures in `$t`):

```bash
    # ---- thumbnails ----
    exts=$("$me" thumbexts)
    for e in pdf mp3 ttf cbz djvu; do check "thumbexts has $e" "$(grep -cx "$e" <<<"$exts")" "1"; done
    check "thumbexts skips glycin (only glycin claims png)" "$(grep -cx png <<<"$exts")" "0"
    magick -size 300x400 xc:white -pointsize 30 -annotate +40+80 'Page one' "$t/it's <b>odd</b> doc.pdf"
    magick -size 200x200 xc:pink "$t/cover.png"
    ffmpeg -loglevel error -y -f lavfi -i sine=duration=1 -i "$t/cover.png" -map 0 -map 1 \
        -c:a libmp3lame -id3v2_version 3 -disposition:v attached_pic "$t/song.mp3"
    font=$(fc-list : file | cut -d: -f1 | grep -m1 '\.ttf$')
    for f in "$t/it's <b>odd</b> doc.pdf:pdf" "$t/song.mp3:audio" "$font:font"; do
        src=${f%:*}; "$me" thumb "$src" "$t/large/$(basename "$src").png" 256 "${f##*:}"
        check "thumb ${f##*:}" "$(file -b --mime-type "$t/large/$(basename "$src").png" 2>/dev/null)" "image/png"
    done
    # sandbox: a thumbnailer can't write outside its temp dir
    mkdir -p "$t/th"; printf '#!/bin/sh\ntouch "%s/escaped"; magick -size 8x8 xc:red "$2"\n' "$t" >"$t/evil.sh"
    chmod +x "$t/evil.sh"; printf '[Thumbnailer Entry]\nExec=%s %%i %%o\nMimeType=application/x-hf-test;\n' "$t/evil.sh" >"$t/th/evil.thumbnailer"
    printf 'hf' >"$t/x.hftest"   # mapped to the fake type below
    HF_THUMBNAILERS=$t/th HF_MIME=application/x-hf-test "$me" thumb "$t/x.hftest" "$t/large/x.png" 256 file
    check "sandbox blocks writes outside" "$([ -e "$t/escaped" ] && echo escaped || echo blocked)" "blocked"
    # failures leave a marker; the next try returns at once; editing the file retries
    printf '[Thumbnailer Entry]\nExec=sh -c "sleep 1; exit 1"\nMimeType=application/x-hf-test;\n' >"$t/th/evil.thumbnailer"
    HF_THUMBNAILERS=$t/th HF_MIME=application/x-hf-test "$me" thumb "$t/x.hftest" "$t/large/y.png" 256 file
    check "fail marker" "$([ -e "$t/fail/himeko-files/y.png" ] && echo yes)" "yes"
    s=$(date +%s%N); HF_THUMBNAILERS=$t/th HF_MIME=application/x-hf-test "$me" thumb "$t/x.hftest" "$t/large/y.png" 256 file
    check "marker skips the retry" "$(( ($(date +%s%N) - s) / 1000000 < 500 ))" "1"
    touch -d '+2 seconds' "$t/x.hftest"; s=$(date +%s%N)
    HF_THUMBNAILERS=$t/th HF_MIME=application/x-hf-test "$me" thumb "$t/x.hftest" "$t/large/y.png" 256 file
    check "edited file retries" "$(( ($(date +%s%N) - s) / 1000000 >= 900 ))" "1"
```

`HF_MIME` is a test-only override of the detected MIME type (document it in the header next to `HF_THUMBNAILERS`).

- [ ] **Step 2: Run** `~/.config/hypr/custom/himeko-files/ops.sh selftest`
  Expected: the existing checks `ok`, the new ones `FAIL` (`usage: see the header` for `thumbexts`), exit 1.

- [ ] **Step 3: Implement `thumbexts`.** Read `[Thumbnailer Entry]` files in the `HF_THUMBNAILERS` dirs (first dir wins
  per file name), skip files named `glycin-*` and entries whose `TryExec` isn't on `PATH`/doesn't exist, collect their
  `MimeType` lists, then print the extensions of `/usr/share/mime/globs2` lines `weight:MIME:*.ext` whose MIME is
  collected and whose pattern is exactly `*.` + `[A-Za-z0-9+_-]+`, lowercased, `sort -u`.

- [ ] **Step 4: Implement the sandboxed `thumb SRC DST SIZE KIND`.**
  1. Marker = `$(dirname DST)/../fail/himeko-files/$(basename DST)`; if it exists and is newer than SRC (`-nt`), exit 1.
  2. KIND `image` → `magick "/input.ext[0]" -auto-orient -thumbnail SIZExSIZE /tmp/gnome-desktop-out.png`;
     KIND `video` → `ffmpegthumbnailer -i /input.ext -o /tmp/gnome-desktop-out.png -s SIZE -c png`, else
     `ffmpeg -loglevel error -y -ss 3 -i /input.ext -frames:v 1 -vf scale=SIZE:-1 /tmp/gnome-desktop-out.png`;
     anything else → MIME (`HF_MIME` or `gio info -a standard::content-type -- SRC`), first entry whose `MimeType`
     list contains it, its `Exec` split on spaces with `%i`→`/input.ext`, `%u`→`file:///input.ext`,
     `%o`→`/tmp/gnome-desktop-out.png`, `%s`→SIZE, `%%`→`%`.
  3. Every command runs as `timeout 20 bwrap --ro-bind /usr /usr --symlink usr/lib /lib --symlink usr/lib64 /lib64
     --symlink usr/bin /bin --symlink usr/sbin /sbin --ro-bind /etc /etc --proc /proc --dev /dev --bind "$sbdir" /tmp
     --ro-bind "$SRC" "/input.$ext" --unshare-all --die-with-parent --new-session CMD…` (`$ext` = SRC's extension
     lowercased, `bin` when none; `sbdir=$(mktemp -d -p "${XDG_RUNTIME_DIR:-/tmp}")`). Put this in `sandbox()`.
  4. Non-empty output → `mkdir -p` + `mv` to DST, exit 0. Otherwise `mkdir -p` the marker dir, `: >marker`, exit 1.
     Always remove `$sbdir`.

- [ ] **Step 5: Run** `~/.config/hypr/custom/himeko-files/ops.sh selftest` — Expected: every line `ok`, exit 0.

- [ ] **Step 6: Commit**

```bash
cd ~/VHyprland-End4-pC && ./sync.sh && git add -A
git commit -m "Himeko Files: thumbnails from the system thumbnailers, sandboxed in bwrap" && git push
```

---

### Task 2: Thumbnails in the app

**Files:** Modify `…/Fs.qml` (kinds, thumbnails section), `…/Thumb.qml`, `…/selftest.qml`; Create
`tools/himeko-files/samples.sh`; Modify `tools/himeko-files/capture.sh` (pass `HF_MUTE=${HF_MUTE:-1}` next to
`HF_ANIMATE`), `…/Theme.qml` (`readonly property bool mute: Quickshell.env("HF_MUTE") === "1"`)

**Interfaces:**
- Consumes: `ops.sh thumbexts`, `ops.sh thumb SRC DST SIZE KIND` (Task 1).
- Produces: `Fs.thumbExts: var` (ext → true), `Fs.thumbFailed: var` (path → true, reassigned on change),
  `Fs.canThumb(item): bool`, `Fs.requestThumb(path: string, kind: string)`.
  `tools/himeko-files/samples.sh DIR` → creates in DIR: `photo.png`, `anim.gif` (3 frames), `clip.mp4` (4 s testsrc +
  sine), `song.mp3` (cover + tags title "Test Song", artist "Himeko"), `doc.pdf` (2 pages "Page 1"/"Page 2"),
  `it's <b>odd</b> name.pdf`, `notes.txt` (300 lines, line 1 is `<b>not bold</b> & <i>plain</i>`), `data.json`,
  `font.ttf` (a system TTF), `pack.zip`, `sub/` (3 files), `fake.txt` (bytes with NULs), `broken.pdf` and
  `broken.mp4` (random bytes), `big.log` (~20 MB: first line "start", then `yes` lines; not sparse, a sparse file
  reads as NULs = binary).

- [ ] **Step 1: Write failing checks** in `selftest.qml` (`run()`):

```js
        // ---- thumbnails (Fs.canThumb) ----
        Fs.thumbExts = { "pdf": true, "mp3": true, "ts": true };
        Fs.thumbFailed = { "/x/bad.pdf": true };
        check("canThumb: image", Fs.canThumb({ isDir: false, suffix: "PNG", path: "/x/a.PNG" }), true);
        check("canThumb: pdf", Fs.canThumb({ isDir: false, suffix: "pdf", path: "/x/a.pdf" }), true);
        check("canThumb: code never", Fs.canThumb({ isDir: false, suffix: "ts", path: "/x/a.ts" }), false);
        check("canThumb: failed", Fs.canThumb({ isDir: false, suffix: "pdf", path: "/x/bad.pdf" }), false);
        check("canThumb: no thumbnailer", Fs.canThumb({ isDir: false, suffix: "zip", path: "/x/a.zip" }), false);
        check("canThumb: folder", Fs.canThumb({ isDir: true, suffix: "", path: "/x/d" }), false);
        check("kinds: new video", Fs.kindOf({ isDir: false, suffix: "ogv" }), "video");
        check("kinds: ttc font", Fs.kindOf({ isDir: false, suffix: "ttc" }), "font");
        check("kinds: comic", Fs.kindOf({ isDir: false, suffix: "cbz" }), "doc");
        Fs.thumbExts = {}; Fs.thumbFailed = {};
```

- [ ] **Step 2: Run** `qs -p …/selftest.qml 2>&1 | grep -E 'FAIL|selftest:'` — Expected: the new checks FAIL
  (`canThumb` not a function), `selftest: N failures`.

- [ ] **Step 3: Implement.** Kinds: video += `flv wmv mpg mpeg 3gp ogv`, font += `ttc`, doc += `cbz cbr cb7 cbt djvu`.
  `Fs` runs `ops.sh thumbexts` once at startup into `thumbExts`. `canThumb`: not a folder, not in `thumbFailed`, kind
  `image`/`video`, or kind ≠ `code` and the lowercased suffix in `thumbExts`. `pumpThumbs` passes the kind and on exit
  ≠ 0 adds the path to `thumbFailed`. `Thumb.qml`: `previewable: Fs.canThumb(item)`, requests with the kind;
  `fillMode` crop for image/video/audio, fit (with ~12 % padding on the tonal tile) for everything else; an audio
  badge (`music_note`) styled like the video play badge.

- [ ] **Step 4: Run** the selftest — Expected: `selftest: 0 failures`.

- [ ] **Step 5: Write `samples.sh` and check the grid visually.**
  Run: `S=<scratchpad>/samples; tools/himeko-files/samples.sh $S && WAIT=6 SIZE="1300 900" tools/himeko-files/capture.sh <scratchpad>/shots/p2-grid.png $S`
  Expected: PDF tiles show the page fitted (both PDFs, the odd name too), `song.mp3` the pink cover with a music badge,
  `font.ttf` a glyph sample, photo/gif/clip as before; `broken.*`, `fake.txt`, `pack.zip` show kind icons.
  Then `ls ~/.cache/thumbnails/fail/himeko-files/` lists the broken files' markers.

- [ ] **Step 6: Commit** — `"Himeko Files: PDF, audio cover and font thumbnails in the grid"`; push.

---

### Task 3: Quick Look overlay

**Files:** Create `…/QuickLook.qml`; Modify `…/Browser.qml` (keys, `lookItem`, `lookStep`, menu entry, Loader, IPC),
`…/Fs.qml` (`appsFor` callback gets the MIME, `previewType`, `stepIndex`), `…/selftest.qml`

**Interfaces:**
- Produces: `Fs.previewType(kind: string, mime: string): string` — one of `image video audio pdf text font folder info`,
  or `""` when the MIME is needed and not known yet. `Fs.stepIndex(i: int, d: int, n: int): int` (clamped, `i < 0` → 0).
  `Fs.appsFor(path, cb)` now calls `cb(apps, mime)` (the bash prints `MIME <type>` first, then `gio mime` of it).
  `Browser.lookItem: var` (null = closed), `Browser.openLook()` (Space and IPC: `tab.focusItem ?? tab.selectedItems[0]
  ?? null`), `Browser.lookStep(d: int)`. `QuickLook.qml`: `required property var item`,
  `required property var tab`, `property Item backdrop`, signals `close()`, `step(int d)`, `open()`; exposes
  `type: string`, and a `body: Item` the bodies may extend with `page`, `pages`, `playing`, `muted`.
  IPC on `files`: `look(name: string)` (select that item and open; `""` closes), `lookStep(d: int)`,
  `lookState(): string` → JSON `{open, type, name, page, pages, playing, muted}` (0/false when not applicable).

- [ ] **Step 1: Write failing checks** in `selftest.qml`:

```js
        // ---- Quick Look rules ----
        check("type: image", Fs.previewType("image", ""), "image");
        check("type: code", Fs.previewType("code", ""), "text");
        check("type: pdf", Fs.previewType("pdf", ""), "pdf");
        check("type: font", Fs.previewType("font", ""), "font");
        check("type: folder", Fs.previewType("folder", ""), "folder");
        check("type: doc waits for mime", Fs.previewType("doc", ""), "");
        check("type: txt", Fs.previewType("doc", "text/plain"), "text");
        check("type: odt", Fs.previewType("doc", "application/vnd.oasis.opendocument.text"), "info");
        check("type: djvu", Fs.previewType("doc", "image/vnd.djvu"), "info");
        check("type: json", Fs.previewType("file", "application/json"), "text");
        check("type: odd audio", Fs.previewType("file", "audio/x-mod"), "audio");
        check("type: zip", Fs.previewType("archive", "application/zip"), "info");
        check("step: next", Fs.stepIndex(2, 1, 5), 3);
        check("step: stops at end", Fs.stepIndex(4, 1, 5), 4);
        check("step: stops at start", Fs.stepIndex(0, -1, 5), 0);
        check("step: missing item", Fs.stepIndex(-1, 1, 5), 0);
```

- [ ] **Step 2: Run** the selftest — Expected: new checks FAIL, others ok.

- [ ] **Step 3: Implement the rules.** `previewType`: kinds image/video/audio/pdf/font/folder map to themselves, `code` →
  `text`; other kinds need the MIME: `text/*`, `application/json`, `application/xml`, `application/x-shellscript`,
  `application/javascript`, `application/toml`, `application/yaml`, `application/x-yaml` → `text`; `video/*` →
  `video`; `audio/*` → `audio`; anything else → `info`.

- [ ] **Step 4: Run** the selftest — Expected: `selftest: 0 failures`.

- [ ] **Step 5: Build `QuickLook.qml` and wire `Browser.qml`.**
  - Space in `Keys.onPressed` (no modifiers) → `openLook()`.
  - Loader (after the info panel, above the menu overlay) active while `lookItem` is set or the close fade runs; on close
    `view.forceActiveFocus()`.
  - `lookStep(d)`: index of `lookItem` in `tab.items`, `Fs.stepIndex`, select it (`tab.select(it, 0)`), `ensureVisible`.
  - If `lookItem.path` leaves `tab.items` (deleted/renamed), set `lookItem = null`.
  - Item menu: `{ icon: "visibility", label: "Quick Look", hint: "Space", action: () => lookItem = one }` after "Open"
    (single item only).
  - `QuickLook.qml`: FocusScope filling the window; dim (`Theme.alpha(Theme.surfaceLowest, 0.45)`) with a MouseArea
    that closes; a `Glass` card (`backdrop: view`, `radius: Theme.rPanel`, `tint: Theme.chromeStrong`) centred; header
    (Thumb 40 px, name, "kind · size · modified" via `Fs.labelOf`/`Fs.size`/`Fs.date`, button "Open with <default
    app name>" (just "Open" when none; folders: "Open"), close `IconButton`). Keys: Space/Esc → close, Left/Up →
    step(-1), Right/Down → step(1), Enter → open (Browser: `activate(item)` then close). It asks `Fs.appsFor` once per
    item and ignores answers for an item it no longer shows.
  - Bodies here: **image** (`Image`, `AnimatedImage` for gif; `sourceSize` = body size × `Screen.devicePixelRatio`,
    fit), **folder** (96 px folder icon, `Fs.countLabel(tab.countOf(path))`, modified), **info** (Thumb 160 px or kind
    icon, kind, size, modified, full path — all `PlainText`). Other types show **info** until their task lands.
  - Card size: image/video keep aspect up to 86 % of window width/height; text/pdf: width `min(760, 86 %)`, height
    86 %; others ~460 × 360. Motion: card `scale` 0.94→1 (`fastSpatial`) + opacity (`effects`), dim opacity
    (`effects`); close fades both (`effects`); body crossfade on item change (`effects`).
  - IPC functions from the Interfaces block; `look(name)` selects by name (like the `select` IPC) then `openLook()`.

- [ ] **Step 6: Check visually** with the samples folder:
  `tools/himeko-files/capture.sh <shots>/p2-ql-image.png $S -- "look photo.png"`, same for `anim.gif`, `sub`,
  `pack.zip`. The odd name has spaces, which capture.sh splits: call `qs ipc --pid $pid call files look "it's <b>odd</b>
  name.pdf"` on the running test window, then run `wincap.qml` directly (`CAP_TITLE="Files (test) — " CAP_OUT=…`).
  Expected: card over the dimmed folder, header with the literal odd name, image fitted, folder "3 items", zip info card.
  Narrow: `SIZE="500 900"` with `look photo.png` — card fits, header elides.

- [ ] **Step 7: Check behaviour over IPC** (on the test pid):
  - `look nonexistent.png` (selects nothing, then the same `openLook()` Space uses) → `"open":false`.
  - `look photo.png`, `lookStep 1` → `name` is the next item in view order; `lookStep 99`-style repeated steps stop at
    the last item.
  - `look notes.txt`, then `rm $S/notes.txt` (restore it after), wait 1 s → `"open":false`.
  Expected: as stated.

- [ ] **Step 8: Run the suite; commit** — `"Himeko Files: Quick Look on Space (images, folders, info)"`; push.

---

### Task 4: Video and audio

**Files:** Create `…/LookMedia.qml`; Modify `…/QuickLook.qml` (body choice)

**Interfaces:**
- Consumes: `QuickLook` body slot and `lookState` (Task 3), `Theme.mute` (Task 2).
- Produces: `LookMedia { required property var item; required property bool video; readonly property bool playing;
  property bool muted }` — `muted` starts as `Theme.mute`.

- [ ] **Step 1: Build `LookMedia.qml`.** `MediaPlayer` + `AudioOutput { muted }`, autoplay on load; video: `VideoOutput`
  fitted, click toggles pause; audio: cover (`Thumb` of the item, else 120 px `music_note`), title/artist from
  `metaData` (`MediaMetaData.Title` / `ContributingArtist`, falling back to the file name), `PlainText`. Control bar:
  play/pause, seek slider (position/duration), `m:ss / m:ss`, mute (`M` key too). `MediaPlayer.errorOccurred` → the
  body switches to the info card. The player stops in `Component.onDestruction`.

- [ ] **Step 2: Check video frames draw** (the spec's open question):
  `HF_ANIMATE=0 tools/himeko-files/capture.sh <shots>/p2-ql-video.png $S -- "look clip.mp4"`.
  Expected: the testsrc colour bars visible in the card. If the video area is black/empty after 3 s, record a ruling and
  switch video to the fallback: the item's thumbnail with the same control bar (audio keeps playing).

- [ ] **Step 3: Check audio**: `capture.sh <shots>/p2-ql-audio.png $S -- "look song.mp3"`; then `lookState`.
  Expected: pink cover, "Test Song", "Himeko", bar running; `"type":"audio","playing":true,"muted":true`.

- [ ] **Step 4: Check silence**: while Step 3's window runs,
  `pactl -f json list sink-inputs | jq --arg p "$pid" '[.[] | select(.properties."application.process.id" == $p) | .mute]'`
  Expected: `[]` or only `true` — never `false`.

- [ ] **Step 5: Check stop on close**: `look ""`, then `tools/himeko-files/perf.sh 5` — Expected: `idle_cpu_pct` < 0.5.

- [ ] **Step 6: Review-focus checks**: `look song.mp3`, `lookStep 1` ×3 quickly (0.1 s apart) through clip/… →
  `lookState` shows the current item with `playing` only when it is media; `look broken.mp4` → `"type":"info"` within
  3 s, window still answers IPC.

- [ ] **Step 7: Run the suite; commit** — `"Himeko Files: Quick Look plays video and audio"`; push.

---

### Task 5: PDF pages

**Files:** Modify `…/ops.sh` (`page`, `pages`, selftest); Create `…/LookPdf.qml`; Modify `…/QuickLook.qml`

**Interfaces:**
- Consumes: `sandbox()` in ops.sh (Task 1).
- Produces: IPC `lookPage(n: int)` (sets the PDF body's page). `ops.sh pages SRC` → page count on stdout (exit 1 if unreadable). `ops.sh page SRC N WIDTH OUT` → PNG of
  page N, WIDTH px wide, at OUT (exit 1 on failure). `LookPdf { required property var item; property int page: 1;
  readonly property int pages }`.

- [ ] **Step 1: Write failing selftest checks** (ops.sh):

```bash
    magick -size 300x400 xc:white -annotate +40+80 'One' xc:white -annotate +40+80 'Two' "$t/two.pdf"
    check "pages" "$("$me" pages "$t/two.pdf")" "2"
    "$me" page "$t/two.pdf" 2 600 "$t/p2.png"
    check "page width" "$(magick identify -format %w "$t/p2.png" 2>/dev/null)" "600"
    head -c 4000 /dev/urandom >"$t/broken.pdf"
    check "broken pdf" "$("$me" pages "$t/broken.pdf" >/dev/null 2>&1; echo $?)" "1"
```

- [ ] **Step 2: Run** `ops.sh selftest` — Expected: the three new checks FAIL.

- [ ] **Step 3: Implement** `pages` (`pdfinfo /input.pdf` in `sandbox`, `Pages:` value) and `page`
  (`pdftoppm -f N -l N -scale-to-x WIDTH -scale-to-y -1 -png -singlefile /input.pdf /tmp/gnome-desktop-out` in
  `sandbox`, move `gnome-desktop-out.png` to OUT).

- [ ] **Step 4: Run** `ops.sh selftest` — Expected: all `ok`.

- [ ] **Step 5: Build `LookPdf.qml`.** Asks `pages` once, renders the current page at the body width ×
  `Screen.devicePixelRatio` into `$XDG_RUNTIME_DIR/himeko-files/pages/<md5(path + modified)>-<n>-<w>.png` (reuse when
  present), shows it fitted with "Page n of N" and small prev/next buttons; Page Up/Down and the wheel flip pages
  (clamped). Ignores answers for a page/item no longer shown. `pages` failure → info card with "Can't preview this
  PDF". Add `page`/`pages` to `lookState`.

- [ ] **Step 6: Check**: `look doc.pdf`, then IPC `lookPage 2` and capture →
  "Page 2 of 2" with "Page 2" visible; `look broken.pdf` → info card with the message; `look doc.pdf` then
  immediately `lookStep 1` → `lookState` type of the next item (not pdf).

- [ ] **Step 7: Run the suite; commit** — `"Himeko Files: Quick Look flips PDF pages (rendered in the sandbox)"`; push.

---

### Task 6: Text and fonts

**Files:** Modify `…/ops.sh` (`text`, selftest); Create `…/LookText.qml`, `…/LookFont.qml`; Modify `…/QuickLook.qml`

**Interfaces:**
- Produces: `ops.sh text SRC` → the first 262144 bytes on stdout, exit 0; exit 3 (and no output) when they contain a
  NUL byte. `LookText { required property var item }`, `LookFont { required property var item }`.

- [ ] **Step 1: Write failing selftest checks** (ops.sh):

```bash
    printf 'hello <b>x</b>\n' >"$t/t.txt"; check "text" "$("$me" text "$t/t.txt")" "hello <b>x</b>"
    printf 'a\0b' >"$t/bin.txt"; "$me" text "$t/bin.txt" >/dev/null; check "binary" "$?" "3"
    yes 'a line of text' | head -c 300000 >"$t/big.log"; check "text is capped" "$("$me" text "$t/big.log" | wc -c)" "262144"
```

- [ ] **Step 2: Run** `ops.sh selftest` — Expected: new checks FAIL.

- [ ] **Step 3: Implement `text`**: `head -c 262144` into a variable-free pipe (temp file is fine), exit 3 when those
  bytes contain a NUL (e.g. compare `wc -c` before and after `tr -d '\0'`), else print them.

- [ ] **Step 4: Run** `ops.sh selftest` — Expected: all `ok`.

- [ ] **Step 5: Build the bodies and check.**
  `LookText`: `Theme.mono` 13 px, line numbers in a dim gutter, `Flickable` scroll, `PlainText`, footer "Showing the
  first 256 KB" when `item.size > 262144`; exit 3 → info card. `LookFont`: `FontLoader { source: "file://" + path }`,
  family name 28 px, "The quick brown fox jumps over the lazy dog" at 14/20/32/48 px, then `ABCDEFGHIJKLMNOPQRSTUVWXYZ
  abcdefghijklmnopqrstuvwxyz 0123456789`; load error → info card.
  Captures: `look notes.txt` → line 1 reads `<b>not bold</b> & <i>plain</i>` literally with numbers 1…;
  `look data.json` → text; `look fake.txt` → info card; `look big.log` → "start" + the 256 KB footer, window answers
  `lookState` within 2 s; `look font.ttf` → samples in that font. Narrow (`SIZE="500 900"`) `look notes.txt`.

- [ ] **Step 6: Run the suite; commit** — `"Himeko Files: Quick Look for text and fonts"`; push.

---

### Task 7: Finish: animations off, performance, README

**Files:** Modify `README.md` (Himeko Files section)

- [ ] **Step 1: Animations off**: `HF_ANIMATE=0 capture.sh <shots>/p2-noanim.png $S -- "look photo.png"` — Expected:
  card fully visible (opacity 1, scale 1) in the capture.

- [ ] **Step 2: Performance** (Quick Look closed): `capture.sh <shots>/p2-perf.png ~/Pictures/Wallpapers; sleep 5;
  perf.sh 10`, twice. Expected: `idle_cpu_pct` ≤ 0.5 and `rss_mb` within noise of Sub-project 1 (257–258 MB;
  run-to-run spread ~6 MB). Record both lines for the commit message.

- [ ] **Step 3: README**: under Himeko Files add
  `- **Previews**: PDF pages, album covers and fonts get real thumbnails (the same thumbnailers Nautilus uses, run in a
  bwrap sandbox). **Space** opens Quick Look: images, video and audio playing, PDF pages, text and fonts; ←/→ walks
  the folder, Enter opens.`

- [ ] **Step 4: Clean up and commit**: `tools/himeko-files/done.sh`; run the suite;
  commit `"Himeko Files: previews finished (README, perf)"` with the perf lines; push.
