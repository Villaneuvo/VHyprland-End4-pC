# Himeko Files: Places (Recent, Starred, pinned folders)

Sub-project 4 of 6 (after Polish & motion, Previews, Properties; then Network, Drag & drop). Code:
`home/.config/hypr/custom/himeko-files/` (live copy in `~/.config/hypr/custom/himeko-files/`).

The user skips question rounds for this roadmap; the calls below are mine, marked *my call* where they go beyond
GNOME Files 47, which is the reference for layout and behaviour (the user's chosen design model).

## Goal

Get back to what you were working on in one click: the files you opened lately, the ones you marked as important,
and the folders you go to all the time, in the same places GNOME and every GTK file dialog use, so a folder pinned in
Himeko Files also shows up in Nautilus and in "Open File" dialogs, and the reverse.

**Success means**

- The sidebar reads like GNOME Files 47: Home, Recent, Starred, Network, Trash; then the pinned folders; then devices.
- **Recent** lists the files and folders you opened lately (from GTK's shared history, `recently-used.xbel`),
  newest first, and files opened from Himeko Files are added to it.
- **Starred** lists everything you starred, from anywhere; a star toggles from the item menu and the Properties header,
  and starred items carry a small star badge.
- **Pinned folders** are GTK's bookmarks (`~/.config/gtk-3.0/bookmarks`): pin and unpin from the item menu, the
  folder's background menu and Ctrl+D; rename, move up/down and unpin from the sidebar row's menu.
- Nothing new polls: no new timers. Changes made elsewhere (a pin made in Nautilus or in another Himeko window, a
  star from another window) arrive through inotify file watches, which cost nothing while idle.

## Anti-goals

- Corrupting GTK's shared files (`recently-used.xbel`, `bookmarks`): other apps read and write them too.
- A slow Recent view: the history holds 1,000 entries (567 KB) here and must open fast.
- Losing the user's current sidebar entries without a way back.

## Sidebar

Order, as GNOME Files 47:

1. **Home**, **Recent** (`schedule`), **Starred** (`star`), **Network** (moves up from the bottom), **Trash** (with
   its count badge).
2. A thin separator, then the **pinned folders** in file order. Each row: icon by path (the XDG folders keep today's
   icons: Documents `description`, Downloads `download`, Music `music_note`, Pictures `image`, Videos `movie`,
   Desktop `desktop_windows`; others `folder`), label = the bookmark's label or the folder name. A pinned folder that
   doesn't exist (unmounted drive) is shown dimmed; clicking it toasts "This folder isn't available".
3. **Devices** as today.

*My call:* "Desktop" is no longer a fixed row (GNOME doesn't show it); the user can pin it. Today's bookmarks file
already holds Documents, Music, Pictures, Videos, Downloads, so those rows stay (in the file's order).

Right-click a pinned row: **Open in New Tab**, **Rename…** (inline field in the row; empty name = back to the folder
name), **Move Up**, **Move Down**, **Unpin**. The rail (narrow sidebar) shows the icons only, as today.

## Pinning

- Item menu on a folder: **Pin to Sidebar** / **Unpin from Sidebar**. Background menu: the same for the current
  folder. **Ctrl+D** toggles the selected folder, or the current folder when nothing is selected (Nautilus' shortcut).
- Writes `~/.config/gtk-3.0/bookmarks` in GTK's format: `file:///percent-encoded/path Optional Label` per line;
  unknown lines (other URI schemes such as `sftp://`, `smb://`) are kept untouched and in place.
- A toast confirms ("Pinned “Projects”"). Pinning the same folder twice does nothing.

## Starred

- Stored by Himeko Files in `~/.local/state/himeko-files/starred`, one absolute path per line. *My call:* not shared
  with Nautilus (its private tracker database is empty here and isn't meant to be written by other apps).
- Toggle: item menu **Star** / **Unstar** (one or several items), and a **star button in the Properties header**
  (top left, as in the recording: outline when not starred, filled primary when starred).
- Starred items show a small filled star badge: top-left of the tile in the icons view, after the name in details.
- Renames and moves done in Himeko Files carry the star to the new path. Changes made elsewhere lose it (like a
  bookmark); missing paths are skipped in the view but kept in the file (a drive may come back).

## Recent

- Source: `~/.local/share/recently-used.xbel` (GTK's recent files, written by GTK apps and Nautilus). Read and written
  through GLib's `BookmarkFile` (Python `gi`, no display needed), never with ad-hoc text edits.
- Shows local (`file://`) entries that still exist, newest first by "modified" (else "visited"), at most 300.
  (*Builder check:* in the real file "visited" stays at the first open for 988 of 1,000 entries, while GTK apps bump
  "modified" on every reopen; Nautilus sorts by it too.)
- Files opened from Himeko Files are added (application "Himeko Files", the file's MIME type), so apps that don't
  record recent files themselves still show up.
- Item menu in Recent adds **Remove from Recent** (removes the entry from the shared history) and **Open Item
  Location** (goes to the parent folder with the item selected); Starred gets **Open Item Location** too.
- Tiles in Recent say "Opened 3 days ago" (the history's time) instead of the modified date.

## Recent and Starred as locations

They open like folders: tab title "Recent" / "Starred", breadcrumb is one crumb with the place's icon, Back/Forward
work, the large title shows the name. Folders and files show as usual (folder counts too), filters and search work.
Not offered there: New Folder, Paste, Compress here, Open Terminal here (nothing is "here"). Rename, Trash, Copy,
Properties, Quick Look work on the real items, and the list reloads afterwards. The details view swaps the Kind column
for **Location** (the parent folder, ~-shortened). Empty states: "Files you open will show here" /
"Star files and folders to find them here", with the place's icon.

## Constraints

- No new dependencies (Python 3 with `gi` GLib is installed; `gio` for MIME types).
- All writes to GTK's shared files go through a temp file + rename in the same folder, keep the file's mode, and
  write through a symlinked file to its target.
- File-derived text (names, labels, paths) shown as plain text.
- Tests on the headless test output only (`tools/himeko-files/capture.sh` … `done.sh`); `ops.sh` tests use temp
  copies (env overrides for the three files), never the real ones.
- Nothing polls. The bookmarks and starred files are watched (inotify, e.g. `FileView { watchChanges: true }`) for
  the whole session; `recently-used.xbel` only while Recent is shown. Missing pins are re-checked whenever the device
  list changes (already tracked by `Fs.refreshPlaces`) and when the sidebar is shown.
- *My calls from the builder check:* pins follow folders renamed in Himeko; stars carry to items inside a renamed
  folder; Recent entries are moved on rename; folders-first sections and sort options stay as they are in
  Recent/Starred; a missing bookmarks file is created on the first pin.

## Testing

- `ops.sh selftest`: recent list from a fixture xbel (order, cap, skips missing and non-file entries), recent add and
  remove (round-trip keeps other entries and the XML valid for GLib), starred add/remove/list (no duplicates, paths
  with spaces/newline-free), bookmarks pin/unpin/rename/move (keeps labels, `sftp://` lines and order, percent
  encoding round-trip, mode and symlink kept), loading 1,000 entries under 300 ms.
- `selftest.qml`: bookmark line parse/format (labels with spaces, encoded paths), the place rows' icon by path, "Opened
  …" text.
- Visual (headless, 1300 px and 500 px): sidebar with pins and a dimmed missing pin, row menu and inline rename,
  Recent and Starred in both views (Location column), empty states, star badge, Properties star.
- Performance: Wallpapers folder RSS/idle as before (no growth while not in Recent/Starred).

## Out of scope

Drag and drop onto the sidebar (sub-project 6), sharing stars with Nautilus, network bookmarks' own rows (kept in the
file, not shown), recent-history privacy settings (clear all, disable), grouping Recent by day.
