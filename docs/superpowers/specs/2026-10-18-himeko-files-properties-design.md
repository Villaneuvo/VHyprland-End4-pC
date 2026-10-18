# Himeko Files: Properties

Sub-project 3 of 6 (after Polish & motion and Previews; then Places, Network, Drag & drop). Code:
`home/.config/hypr/custom/himeko-files/` (live copy in `~/.config/hypr/custom/himeko-files/`).

The user asked for "detailed Properties (Alt+Enter)" and chose to skip question rounds, so the calls below are mine.
Reference: the Nautilus Properties dialog (General, Permissions, Open With) plus a Details tab for media metadata.

## Goal

Everything you'd want to know or change about a file without leaving the folder: full size and dates, real type,
permissions you can change, which app opens it (and changing that), and the metadata inside photos, songs, videos,
PDFs and fonts.

**Success means**

- **Alt+Enter** (and "Properties" in the item menu) opens a Properties card for the selection; **Esc** closes it.
  F11 keeps toggling the info panel (today Alt+Enter also toggles it; that moves to Properties).
- General shows type, exact size, folder contents counted live, parent folder, link target, all three dates in full,
  and free space for folders; several selected items show totals.
- Permissions can be changed in place for files you own, the same choices Nautilus offers.
- Open With lists the apps for the file's type and can make one the default.
- Details shows image, audio/video, PDF and font metadata.
- Nothing runs while the card is closed; a folder count still running is stopped when it closes.

## Anti-goals

- Changing permissions or defaults by accident (a click on a tab or a label must never change anything).
- Freezing on huge folders (counting `~` or `/usr` must stay responsive and stoppable).
- Parsing untrusted files outside the sandbox (metadata readers run in the same `bwrap` sandbox as thumbnails).
- Rendering file-derived text (names, tags, EXIF) as markup.

## The card

Same overlay pattern as Quick Look: the folder dims, a Glass card in the middle (about 560 px wide, height to content,
at most 86 % of the window), header with the item's thumbnail/icon, name and type, then a row of tab chips: **General**,
**Permissions**, **Open With** (one file selected), **Details** (one file with metadata). Esc or a click outside closes it;
Ctrl+Tab / Ctrl+Shift+Tab switch tabs. The tab last used is remembered for the session. Motion: the Quick Look tokens
(card pop + fade, dim fade); nothing animates with animations off. Works down to the 500 px window.

## General

| Row | One item | Several items |
|---|---|---|
| Name | the name, editable (Enter renames through the existing rename op; the card follows the renamed item) | "12 items (3 folders, 9 files)" |
| Type | `gio info` description and MIME type, e.g. "PNG image (image/png)"; folders "Folder" | — |
| Size | files "2.4 MB (2,412,345 bytes)"; folders "124 items, totalling 3.2 GB", counted live | total of all, folders counted live |
| Link target | for symlinks: where it points (or "broken link") | — |
| Location | the parent folder, click to go there | the common parent |
| Modified / Accessed / Created | full dates, e.g. "Saturday, 18 October 2026, 16:30" (Created only when the filesystem records it) | — |
| Free space | folders: "241 GB free of 466 GB" on that filesystem | — |

Live folder counting: one `find` process per card streams running totals (items, bytes) every few thousand entries
and once at the end; the row shows "Counting… 52,310 items, 4.1 GB" until done. It doesn't follow symlinks, counts
hidden files (like Nautilus), skips what it can't read, and is killed when the card closes or the selection changes.

## Permissions

- Owner and group names ("You" when it's you).
- Access for **Owner**, **Group**, **Others**, as Nautilus words it: files "None / Read-only / Read and write"; folders
  "None / List files only / Access files / Create and delete files". Plus for files **"Allow executing file as program"**.
- Changes apply at once with `chmod` (one `ops.sh chmod MODE PATH…` call), only the bits shown are touched (setuid etc.
  kept), and the rows refresh from `stat` afterwards. Several selected items: each row shows the shared value or
  "Mixed"; choosing a value applies it to all. *My call:* when the selection holds both files and folders, there are two
  access rows per class, **Files** and **Folders** (as Nautilus does), each applied with its own `chmod` call.
- Read-only when you don't own (every) item: "Only the owner can change these permissions", and for symlinks
  (permissions of a link mean nothing).
- Not here: changing owner/group (needs root), applying to enclosed files recursively, ACLs.

## Open With (one file)

- The apps registered for its MIME type (the existing `Fs.appsFor`), the default marked; each row has
  **Set as default**. *My call:* only that exact type changes (like Nautilus), and there is no Reset (picking another app
  is the undo; the target file also holds the user's own hand-written choices, which a Reset couldn't tell apart).
- Setting the default writes `MIME=app.desktop` under `[Default Applications]` in the file this session reads first:
  `~/.config/<desktop>-mimeapps.list` (here `hyprland-mimeapps.list`, which is in the dotfiles) when
  `XDG_CURRENT_DESKTOP` is set and that file exists, else `~/.config/mimeapps.list`. (`xdg-mime default` writes
  `mimeapps.list`, which the Hyprland file overrides, so it would silently not work for types that file lists.)
- The write replaces that type's line or adds one under `[Default Applications]`; comments and every other line stay
  as they are.
- A toast confirms with the type's description ("PNG images now open with Image Viewer"); the list refreshes.

## Details (one file with metadata)

One `ops.sh meta FILE KIND` call prints `Label<TAB>Value` lines; the tab lists them (selectable text). Readers run in the
thumbnail sandbox:

| Kind | Reader | Rows |
|---|---|---|
| image | `magick identify` | Dimensions, Color, Bit depth, then EXIF if present: Camera (make + model), Taken, Exposure, Aperture, ISO, Focal length, Orientation |
| audio / video | `ffprobe -of json` | Duration, Title, Artist, Album, Year, Video (codec, W × H, fps), Audio (codec, channels, sample rate), Bitrate |
| pdf | `pdfinfo` | Pages, Title, Author, Subject, Creator, Producer, Page size, PDF version |
| font | `fc-scan` | Family, Style, Version, Foundry |

Empty values are left out; if nothing is found the tab isn't shown.

## Constraints

- No new dependencies (all readers are installed; `exiftool`/`mediainfo` are not and aren't needed).
- Properties lives in its own file(s), loaded on demand; `Browser.qml` gets the key, the menu entry, the Loader and IPC.
- All file-derived text shown as plain text.
- Tests on the headless test output only (`capture.sh` … `done.sh`); `HF_MUTE` unaffected.

## Testing

- `ops.sh selftest`: `meta` rows for a generated PNG (dimensions), MP3 (duration, title, artist), PDF (pages, title) and a
  system font (family, style); `chmod` changes only the given bits on a temp file; `mimedefault` writes and replaces the
  entry (keeping comments and other lines) in a temp config dir (`XDG_CONFIG_HOME` override) and picks the desktop-specific file when present;
  `dirsize` prints running totals and a final line matching `find | wc -l` / `du -sb --apparent-size` on a temp tree.
- `selftest.qml`: mode ↔ access level mapping for files and folders (incl. executable, mixed), size text with exact bytes
  and thousands separators, full date text.
- Visual (headless): General for a file, a folder (counting then done), several items; Permissions editable and
  read-only (`/etc/hostname`); Open With with the default marked; Details for photo, song, video, PDF, font; 500 px.
- Behaviour over IPC: Alt+Enter path with nothing selected does nothing; changing access really changes `stat -c %a`;
  closing during a count kills the `find`.

## Left to the builder

Component split, exact layout and control styling (chips, toggles in the Glass/IconButton look), the streaming
interval, which EXIF tags map to which label (the table above is the minimum), how the remembered tab is stored.

## Out of scope

Changing owner/group, recursive permission changes, ACLs, checksums, "open with other application" (custom command),
editing tags/EXIF, properties for items in Trash beyond General.
