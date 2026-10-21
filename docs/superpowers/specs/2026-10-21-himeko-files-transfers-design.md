# Himeko Files: Drag and drop, progress and conflicts

Sub-project 6 of 6, the last (after Polish & motion, Previews, Properties, Places, Network). Code:
`home/.config/hypr/custom/himeko-files/` (live copy in `~/.config/hypr/custom/himeko-files/`).

The user skips question rounds for this roadmap, so the calls below are mine. They're marked *my call* where they go
beyond GNOME Files (Nautilus 50 is installed here), which is the reference for layout and behaviour.

## Goal

Move files around the way hands expect: drag them onto a folder, the sidebar, a tab or another app, and drop files
from other apps into Himeko Files. Long copies show their progress and can be cancelled. When a name is already taken,
you choose what happens. Today:
- paste runs blind: one toast, no progress, no cancel;
- clashing names are always renamed "name (2)";
- nothing can be dragged.

**Success means**

- **Drag:** tiles and rows can be dragged:
  - onto a folder (tile, row, breadcrumb, sidebar place, pin, drive or connected server);
  - onto Trash;
  - into another tab;
  - out to other apps (Dolphin, Chrome, Telegram…).

  Files dragged in from other apps land where they are dropped.
- **Hover:** a folder lights up under the pointer, and opens after a short hover (spring-loaded), so you can dig into
  a tree while dragging.
- **Copies and moves** (paste, drag and drop) show in an **operations button** in the header. Its ring fills as they
  run, and its popover lists each one: what, where, bytes so far, time left, and a cancel button. They work the same
  onto and from servers.
- **Conflicts:** a taken name asks, GNOME-style: **Skip**, **Keep Both**, **Replace** (files) or **Merge** (folders),
  with **Apply to All**. Replaced files go to Trash, not into the void.
- **Other long jobs** (Trash, Delete, Compress, Extract) show in the same popover while they run.
- **Undo** still undoes the last copy or move, precisely:
  - it removes only what the job added (to Trash on local disks; deleted on servers, which have no Trash);
  - it moves moved items back;
  - it restores replaced originals from Trash.

  Originals overwritten where there was no Trash can't come back, and the dialog said so.

## Anti-goals

- Losing data:
  - a cancelled or failed copy must not leave half files behind;
  - Replace must never destroy what it replaces on a local disk;
  - a move must never delete a source before its copy is complete.
- A frozen window during a big transfer. The window never does file I/O itself.
- Surprise moves across drives. Dragging between filesystems copies, as GNOME does.

## Transfers (my calls)

- **One helper, `transfer.py`** (Python stdlib + `gio` for Trash), dispatched by `ops.sh`. It replaces the
  `cp`/`mv` path of `ops.sh paste`.
  `transfer.py copy|move|auto DEST SRC…` speaks JSON lines like `network.py`:
  - **Scanning:** `{"scanning": files}` while it counts, then `{"total": bytes, "files": n}`.
  - **Progress:** `{"progress": {"bytes", "file"}}`, at most every 150 ms.
  - **Conflict:** `{"ask": "conflict", …}` with both items' name, kind, size and modified time. The app answers with
    one line: `{"choice": "skip"|"keep"|"replace"|"merge", "all": bool}` or `{"cancel": true}`.
  - **Per top-level source:** `{"made": [src, created]}`, or `{"skipped": src}`.
  - **Undo log, as it happens:** `{"undo": {"created": path}}` for each item it created (inside a merge, each one it
    put there), and `{"undo": {"moved": [from, to]}}` for each item it moved. At the end,
    `{"undo": {"replaced": path, "trash": uri}}` for each original that Replace sent to Trash; one look at `trash:///`
    resolves them all.
  - **Failed items:** an item that fails (permission denied, vanished, a name the target can't hold) is skipped and
    reported as `{"failed": {"path", "error"}}`, and the job goes on (*my call*, builder check). "No space left" stops
    the job.
  - **End:** `{"done": true}` (with how many failed), `{"error": msg}` or `{"cancelled": true}`.
- **auto** (drag and drop) moves an item when it is on the same filesystem as the destination (`st_dev`), and copies
  it otherwise, as GNOME does. Keyboard modifiers aren't readable during a Wayland drag, so there is no Ctrl/Shift
  override; Undo is the safety net. **move** across filesystems copies, then deletes the source only after its copy
  completed. **copy** keeps symlinks as links, and keeps times and modes on local disks. On servers (gvfs FUSE) only
  the data is copied, as today.
- **Cancel** (the popover's ✕, or `SIGTERM` to the helper) stops after the current block. It removes the file being
  written and reports what was already made, so Undo covers the finished part.
- **Hidden part files:** files are written under a hidden name next to their target (`.name.himeko-part`) and
  renamed into place when complete. Even a hard kill never leaves a half file under the real name (*my call*,
  builder check).
- **Keep Both** gives the "name (2)" rule `ops.sh` already uses.
- **Replace** sends the old item to Trash first (`gio trash`) when the place has one. The conflict ask carries
  `canTrash`, from GIO's `access::can-trash`. Where there is no Trash (a server, a system mount, a drive without a
  Trash folder) it overwrites, and the dialog says so before you choose.
- **Merge** copies a folder's contents into the existing folder, asking again for each clash inside, unless Apply to
  All is set.
- Copying into itself (a folder into its own subfolder) is refused, as today. Dropping items into the folder they're
  already in does nothing.

## Operations button and popover

GNOME 47 layout in Himeko glass:
- **The button:** it sits in the header next to search and appears only while a job runs or has just finished. It is
  a progress ring around an icon:
  - `arrow_downward` for copies and moves, `delete` for Trash;
  - the ring is indeterminate while scanning or for jobs without byte counts;
  - when everything is done the button shows a check for 3 s, then hides.
- **The popover:** one boxed row per job.
  - **Title:** "Copying “a.txt” to “Pictures”", "Copying 12 files to “Pictures”", "Moving …",
    "Moving 3 items to Trash", "Deleting 3 items", "Compressing 3 items", "Extracting “x.zip”".
  - **Subtitle:** "Preparing…" while scanning, then "1.2 GB of 3.4 GB — 2 minutes left"; "Done", or gvfs'/the
    helper's error.
  - **The row** also has a thin progress bar and a cancel button (✕).
- **Lifetime:** finished jobs fade out after 3 s. Failed ones stay until dismissed.
- **Partial failures:** a job where some items failed ends as "Copied 10 of 12 items", with the failures listed under
  it (name and reason).
- **Closing the window while jobs run** (last tab, Ctrl+W, the window's close) asks "Operations are running", with
  **Cancel Them and Close** / **Keep Open** (*my call*, builder check). The helper runs as the window's child, and a
  closing window would kill it before it can clean up.
- The old "Copying 3 items…" toast goes. The finishing toast ("Copied 3 items" with **Undo**) stays.

## Conflict dialog

A glass dialog over the window (the same family as the password dialog):
- **Title:** "Replace “name”?" for a file, "Merge Folder “name”?" for a folder.
- **Message:**
  - files: "A file with the same name already exists in “Dest”.";
  - folders: "A folder with the same name already exists in “Dest”. Merging asks before replacing any files in it.";
  - where there is no Trash, Replace adds "There's no Trash here: the existing file will be overwritten."
- **Comparison:** two boxed rows, **Original** and **Replacement**, each with the icon and "size · modified date". A
  newer or larger side gets a dim "newer" or "larger" tag.
- **Apply to All:** a switch, shown only when more items are still to go.
- **Buttons:** **Cancel** (stops the whole job), **Skip**, **Keep Both**, and **Replace** or **Merge** (the
  destructive style). Enter is Keep Both, the non-destructive default. Esc is Cancel.

## Drag and drop

- **Starting a drag:**
  - Press and drag a tile or row past the usual threshold. If it wasn't selected, it becomes the selection.
  - The selection is dragged as `text/uri-list` (`file://` URIs) with Copy|Move offered.
  - Drag image: the first item's thumbnail or icon with a count badge (cookie shape) when there are several.
  - Items in Recent and Starred drag like any file. The Network page's rows aren't draggable (*my call*).
- **Drop targets and hover feedback:**
  - folder tiles and rows: primary outline; spring-open after 800 ms;
  - the view's background: drop into the current folder; a soft primary border around the view;
  - breadcrumbs: highlight, spring-open after 800 ms;
  - tabs: highlight, switch after 800 ms; a drop goes into that tab's folder;
  - sidebar rows: Home, pins, drives, Connected servers and Trash. Recent, Starred and Network don't accept drops, and
    network pins accept only when connected.
  - Dropping a folder onto the gap between pins, or below the last pin, pins it; a line marks the spot.
  - A file tile is not a target: it means its folder.
- **What a drop does:**
  - onto Trash: Trash, with Undo;
  - anywhere else: `transfer.py auto`;
  - into the folder the items are already in: nothing;
  - from other apps: the same rules for `file://` URIs. Anything else (web links, raw images) gets the toast "Only
    files can be dropped here".
- **Dragging out:** the same `text/uri-list`. Files on a server go out as their FUSE paths, which other apps can open.
- **Scroll while dragging:** dragging near the top or bottom edge of the view scrolls it.

## Constraints

- No new dependencies: Python 3 stdlib, `gio`, Qt Quick's `Drag`/`DropArea`/`DragHandler`.
- No new polling. Progress comes from the helper's lines. The spring-open and fade-out are single-shot timers tied
  to a hover or a finished job.
- The window never touches the disk itself. Every transfer runs in a helper process. The `st_dev` check runs in the
  helper too.
- File-derived text is `textFormat: Text.PlainText`.
- Tests:
  - run on the headless output only;
  - the helper's tests use temp folders on two filesystems (`~/.cache`, ext4, and `/tmp`, tmpfs) and a scratch
    `XDG_DATA_HOME` for Trash;
  - server copies use the private-bus `testdav.py` setup (minimal bus config: never the keyring).

## Testing

- **`ops.sh selftest` (transfer.py):**
  - a tree copy with progress lines and totals;
  - `auto` moves on one filesystem and copies across (`~/.cache` → `/tmp`);
  - a move across filesystems deletes sources only after the copy;
  - conflicts: skip, keep (name (2)), replace (the old file lands in the scratch Trash), merge with a clash inside,
    and Apply to All;
  - a cancel mid-file leaves no partial file and reports what was made;
  - symlinks stay links;
  - a copy onto a dev server mount reports progress.
- **Headless UI (IPC hooks, since a pointer drag can't be faked without touching the user's screen):**
  - `dropUris(target, uris)` runs the same code a drop runs;
  - `dragHover(target)` shows the hover state and spring-opens;
  - the operations button and popover during a throttled copy (`HF_SLOW_COPY` test hook), then done;
  - the conflict dialog (file and folder; Apply to All shown and hidden);
  - a drop onto Trash and a drop that pins.
- **The user tries real mouse drags at the end:** within the app, from Dolphin, and out to Chrome. This is the one
  thing only a pointer can test.
- **Performance:** idle as before (nothing new runs while idle). The operations button and popover don't exist until
  a job starts.

## Out of scope

- A drop menu (Move Here, Copy Here, Link Here) and modifier-key overrides: Wayland doesn't give them to us during a
  drag.
- Creating links by drag.
- Rubber-band changes.
- Queueing jobs one after another (they run side by side, as in GNOME).
- Pausing.
- Desktop notifications when a long job ends.
- Downloading web URLs dropped from browsers.
