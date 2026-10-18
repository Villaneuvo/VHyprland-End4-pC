# Himeko Files: Previews

Sub-project 2 of 6 in making Himeko Files the daily file manager (after Polish & motion; then Properties,
Places, Network, Drag & drop). Code: `home/.config/hypr/custom/himeko-files/` (live copy in
`~/.config/hypr/custom/himeko-files/`).

The user asked for "file previews, like Nautilus" and chose to skip a question round ("better kita selesaikan dulu
to do listnya"), so the calls below are mine unless marked as theirs. Reference: Nautilus thumbnails and GNOME Sushi
(Space preview), macOS Quick Look.

## Goal

See what a file is without opening it: real thumbnails for the file types Nautilus thumbnails, and a Quick Look
preview on Space that shows the file large, plays media, flips PDF pages and shows text, without leaving the
folder.

**Success means**

- PDFs (and comics, DjVu), audio with cover art and fonts show real thumbnails in the icons view, the details list and
  the info panel, from the same system thumbnailers Nautilus uses; images and videos keep working as now.
- Space opens Quick Look on the focused item; Left/Right walks through the folder; Space/Esc closes; Enter opens.
- Quick Look shows: images (animated GIFs move), videos and audio playing with controls, PDF pages, text and code,
  font samples, folders, and a fallback card for everything else.
- Untrusted files never get parsed outside a sandbox by our thumbnail and page-render processes.
- With Quick Look closed nothing new runs: idle CPU stays ~0 % and memory stays within noise of Sub-project 1
  (Wallpapers ~257 MB).

## Anti-goals

- A preview that blasts or hangs: a broken or huge file must never freeze the window (all decoding async or in
  processes; text capped).
- Re-trying the same broken file every time a folder is shown.
- Rendering file content as markup (a text file or file name containing `<b>` must show literally).

## Part A: Thumbnails from the system thumbnailers

### Which files get one

`ops.sh thumbexts` (new) prints the file extensions that have a thumbnailer, worked out once at startup:

1. MIME types claimed by `*.thumbnailer` files in `~/.local/share/thumbnailers` and `/usr/share/thumbnailers`
   (the freedesktop spec's `[Thumbnailer Entry]` with `TryExec`, `Exec`, `MimeType`), skipping entries whose
   `TryExec` isn't installed and the `glycin-*` ones (glycin starts its own bwrap sandbox, which can't nest inside ours;
   images go through our own path anyway).
2. Extensions for those types from shared-mime-info's globs (`/usr/share/mime/globs2`, simple `*.ext` globs only),
   minus the `code` kind's extensions (*my call*: globs2 maps `*.ts` to video/mp2t, which would send every TypeScript
   file to a video thumbnailer). Other stray matches (e.g. `go.mod` → audio/x-mod) cost one failed try, then the
   fail marker stops them.

`Fs` keeps that set. A tile asks for a thumbnail when its extension is an image or video kind (as now) or is in the
set. Today that adds: PDF, comics (cbz/cbr/cb7/cbt), DjVu, Illustrator, audio (mp3, flac, ogg, m4a, …), fonts
(ttf, otf, woff, ttc). *My call:* the kind lists grow to match, so badges, the crop/fit rule and Quick Look agree:
video gains flv, wmv, mpg, mpeg, 3gp, ogv; font gains ttc; doc gains cbz, cbr, cb7, cbt, djvu. Installing a new thumbnailer (e.g. LibreOffice's) extends it with no code change.

### How one is made (`ops.sh thumb SRC DST SIZE`)

- Image-kind extensions: ImageMagick as now. Video-kind extensions: ffmpegthumbnailer, else ffmpeg, as now.
  (*My call:* routed by our kind lists, not by MIME family: gio calls DjVu and TIFF `image/*`, and DjVu needs
  papers-thumbnailer.)
- Anything else: MIME type from `gio info -a standard::content-type`, then the first matching thumbnailer entry
  (user dir first). Its `Exec` gets `%i` (path), `%u` (file URI),
  `%o` (output), `%s` (size), `%%`.
- **Every** one of these runs inside `bwrap`, ImageMagick and ffmpeg included (and Quick Look's `pdftoppm`/`pdfinfo`): read-only `/usr` and `/etc`, the source bound read-only at
  `/input.<ext>` (extension kept, some thumbnailers look at it), a private temp dir bound at `/tmp`, output written to
  `/tmp/gnome-desktop-out.png` inside it, `--unshare-all --die-with-parent --new-session`. No home, no network.
  Measured: +~30 ms per thumbnail. The output name matters: Ubuntu's AppArmor profile only lets `papers-thumbnailer`
  write `/tmp/gnome-desktop-*` (anything else fails silently with EACCES).
- 20 s timeout per thumbnail (a thumbnailer stuck on a broken file must not hold a slot forever).
- Result goes to the freedesktop cache as now (`~/.cache/thumbnails/large/<md5 of URI>.png`, 256 px, shared with
  Nautilus/Dolphin).

### Failures

- A failed thumbnail writes an empty marker `~/.cache/thumbnails/fail/himeko-files/<md5>.png`; `ops.sh thumb` exits
  at once while the marker is newer than the file (so editing the file retries it).
- `Fs` also remembers failures for the session, so a tile showing a failed file doesn't spawn a process again.
- Failed or not-yet-made thumbnails show the kind icon tile, as now.

### How they look

- Images, videos: cropped to fill the tile, as now (videos keep the play badge).
- Audio cover art: cropped to fill, with a small music-note badge like the video one.
- PDF/document pages and fonts: fitted (not cropped) on the kind's tonal tile with a little padding, so a page reads
  as a page.

## Part B: Quick Look

### Opening and moving

- **Space** opens Quick Look on the focused item (`tab.current`, else the first selected item); nothing focused =
  nothing happens. Space again, **Esc**, or a click outside the card closes it.
- **Left/Right** (and Up/Down) go to the previous/next item in the view's current order, moving the selection with
  it, so closing leaves you on the last previewed item. They stop at the ends (no wrap).
- **Enter** opens the item (folders: navigate into it) and closes Quick Look. The header's **Open with \<default app\>**
  button does the same for files.
- The item menu gets "Quick Look" with hint "Space", after "Open".
- Typing in the rename field or search field never triggers Quick Look (Space types a space there).

### The card

An overlay inside the window: the folder dims behind a Glass card (same materials as the info panel and menus).
Header: icon/thumbnail, file name, "kind · size · modified" line, Open-with button, close button. The body depends
on the type. The card is sized to the content: media and images keep their aspect ratio up to 86 % of the window's
width and height; text and PDF use a reading width (about 760 px, less in narrow windows) and the full available
height. Works down to the 500 px window from Sub-project 1.

### Body per type

The type comes from the item's kind (extension); for kinds where the extension isn't enough (`doc`, unknown
`file`) the MIME type decides, from the same `gio mime` call that finds the default app.

| Type | When | Shows |
|---|---|---|
| image | image kind or `image/*` | The image fitted, decoded at the card's size (not full resolution). GIFs animate. |
| video | video kind or `video/*` | Plays at once with sound, like Sushi/Quick Look (`HF_MUTE=1` silences it, see Constraints). Click = pause/play; a bar with play/pause, position/seek, time, mute. |
| audio | audio kind or `audio/*` | Cover art (the thumbnail, else a big music icon), title and artist from the file's tags, plays at once; same controls. |
| pdf | pdf kind | One page at a time, rendered by `pdftoppm` (sandboxed like thumbnails) at the card's size into `$XDG_RUNTIME_DIR/himeko-files/pages/`; "Page 2 of 14"; Page Up/Down, scroll wheel or small arrows flip pages. Page count from `pdfinfo`. |
| text | code kind, or a `text/*` / JSON / XML / YAML / TOML / shell MIME type | The first 256 KB in the monospace font, with line numbers, scrollable, never as markup; "Showing the first 256 KB" when cut. A NUL byte in it means it's binary: fall back to the info card. |
| font | font kind | Font name, then "The quick brown fox jumps over the lazy dog" at four sizes and the alphabet/digits, loaded with `FontLoader` from the file. |
| folder | folder | Big folder icon, item count (the counts from Sub-project 1), modified date. |
| info | everything else (archives, apps, office files, disk images, …) | The thumbnail if one exists, else the big kind icon; kind, size, modified, full path. |

Media stops and is released when you move to another item or close Quick Look.

### Motion

Using Sub-project 1's tokens: the card scales 0.94 → 1 and fades in (`fastSpatial` scale, `effects` fade), the dim
fades in (`effects`); closing fades both out (`effects`). Moving to another item crossfades the body (`effects`).
Nothing animates when animations are off system-wide.

## Constraints

- No new dependencies: `bwrap`, `pdftoppm`/`pdfinfo` (poppler-utils), `ffmpegthumbnailer`, ImageMagick, QtMultimedia
  (ffmpeg backend) are installed. QtMultimedia was checked from `qs -p`: it loads, plays, reads duration and tags.
- Quick Look lives in its own file(s) loaded on demand; nothing of it exists while closed. `Browser.qml` only gets the
  key handling, the menu entry and the Loader.
- All file-derived text (names, file content, tags) is shown as plain text.
- Tests run on the headless test output only (`tools/himeko-files/capture.sh` … `done.sh`), never on the user's screen.
- *My call:* `HF_MUTE=1` (like `HF_ANIMATE`) mutes Quick Look media; `capture.sh` sets it by default, so a test never
  plays sound through the user's speakers.
- *My call:* QtMultimedia was only checked headless (it plays and reads tags), not that `VideoOutput` draws frames in a
  Quickshell window. The plan checks that first; if it can't, video falls back to the thumbnail with the audio
  controls.

## Testing

- `ops.sh selftest`: `thumbexts` contains pdf, mp3 and ttf and not png-only glycin leftovers; thumbnails are made for a
  generated PDF, MP3 with cover and a system font; a fake thumbnailer (via a test override of the thumbnailer dirs)
  that tries to write into `$HOME` fails and leaves nothing behind; a failing file leaves a marker and the second try
  returns at once without running the thumbnailer; touching the file clears that.
- `selftest.qml`: the type rule (kind + MIME → type) and the Left/Right stepping (ends don't wrap).
- Visual (captures on the headless output): grid with PDF/audio/font thumbnails; Quick Look for each type, PDF on page
  2, text with markup-looking content, at 1892 px and 500 px wide; animations off.
- Performance: idle CPU and RSS on `~/Pictures/Wallpapers` with Quick Look closed, against Sub-project 1's numbers;
  CPU back to ~0 after closing a playing video.

## Left to the builder

Component split, exact sizes/paddings and control styling (match the existing Glass/IconButton look), how the page
cache is named and cleaned (it's on tmpfs), how the thumbnailer list is passed from `ops.sh` to `Fs`.

## Out of scope

Syntax highlighting, Markdown rendering, archive listings, office documents without an installed thumbnailer,
multi-item Quick Look, regenerating stale thumbnails of edited files (existing behaviour; Nautilus overwrites them),
editing anything from Quick Look.
