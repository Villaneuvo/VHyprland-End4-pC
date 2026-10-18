# Himeko Files: Properties redesign (Nautilus 47 layout)

Follow-up to sub-project 3 (`2026-10-18-himeko-files-properties-design.md`). The user didn't like the first design
(tab chips over a label/value grid) and recorded GNOME Files' Properties dialog as the model
(`~/Videos/recording_2026-10-18_16.55.13.mp4`): "aku kurang suka designnya, coba deh liat design yang di files, so far
aku suka mungkin bisa nih dijadikan inspirasi". Everything the first version does stays (data, guards, sandbox,
IPC); this changes how it looks and how you move around it, and adds the two things the recording uses that we lacked:
changing the group and "Change Permissions for Enclosed Files". Calls not taken from the recording are marked *my call*.

## What the recording shows (and we copy)

- A **hero** at the top, centred: the big icon/thumbnail with a round **pencil badge** (rename), the name in bold,
  "49,485 items, totalling 598.9 MB" with a small **spinner** while counting, "258.5 GB Free" below.
- **Boxed lists**: rounded groups of rows on a lighter surface, rows split by a thin gap. A property row is a small dim
  title above its value ("Parent Folder" / "/home/villaneuvo/"), with an optional icon button at the right (open folder).
- **Navigation instead of tabs**: a row "Permissions … Create and Delete Files ›" opens a page that slides in, with a
  back chevron, a centred bold title and the close button.
- **Dropdown rows**: "Access … Create and Delete Files ⌄" opens a small popover list of choices with a check on the
  current one; the Group list has a search field at the top.
- A **"Change Permissions for Enclosed Files…"** button row (folders) opening a page whose header is **Cancel** (pill) /
  title / **Change** (filled primary pill), with Owner / Group / Others sections of Files and Folders dropdowns.
- Owner's access offers no "None" (Read-Only / Read and Write; folders List Files Only / Access Files / Create and
  Delete Files).

## Layout

The card keeps Himeko's glass (dim behind, `Glass` card, Quick Look motion), about **460 px** wide, height to content
up to 86 % of the window, the page area scrolls when taller. Boxed groups: radius 14, rows ≥ 52 px, row surface
`Theme.alpha(Theme.text, 0.05)` (hover 0.08), 2 px between rows, 12 px between groups, small bold section titles
("Other Users", "Owner") above a group.

### Main page

- **Header bar**: left empty (*my call*: the star for favourites comes with Places, sub-project 4); right **Open**
  (`open_in_new`: opens the item like Enter; folders navigate into it) and **close**.
- **Hero**: Thumb 96 px (photos show the picture; radius 18) with the pencil badge (one item, not in Trash, not the
  current folder) → the name turns into the rename field in place; name 18 px bold; subtitle — folders and several items:
  the live count with a spinner while counting; files: "PNG image · 2.3 MB"; third line — folders: "258.5 GB Free";
  several items: "3 items (1 folder, 2 files)" as the title instead of a name.
- **Group "where"**: *Parent Folder* (value with ~, open-folder button → go there and close); *Link Target* for symlinks.
- **Group "when"**: *Modified*, *Created* (when known) — full dates as before. (*my call*: Accessed dropped, the
  recording doesn't show it.) Files also get *Size* here with the exact bytes ("2.3 MB (2,412,345 bytes)").
- **Group "more"** (navigation rows, each `›`):
  *Permissions* — value = owner's access ("Create and Delete Files", "Read and Write", "Mixed"); not in Trash.
  *Open With* — value = default app name; one file, not in Trash.
  *Details* — value = what it is ("Image", "Audio", "Video", "PDF", "Font"); only when metadata rows exist.

### Permissions page ("Permissions")

- Group: *Owner* (value "villaneuvo (You)"), *Access* (dropdown, no "None").
- Group: *Group* (dropdown with search: the groups you're in, from `id -nG`, when you own every item; otherwise a plain
  value), *Access* (dropdown).
- "Other Users" group: *Access* (dropdown).
- Files: a switch row *Allow Executing File as Program*.
- Folders (one folder you own): a button row *Change Permissions for Enclosed Files…* → the Enclosed page.
- Files and folders selected together: each Access row becomes two rows *Files* and *Folders* (as on the Enclosed page).
- Read-only (not yours, a link, unreadable): dropdowns show values without the chevron; the note as before at the bottom.
- Changing the group runs `chgrp` (allowed without root for your own files and groups you belong to), refreshes the rows.

### Enclosed page ("Change Permissions for Enclosed Files")

- Header: **Cancel** (back without changes) / title / **Change** (primary pill; spinner while running).
- Owner, Group, Others sections, each *Files* and *Folders* dropdowns. Start values come from the **umask**, as Nautilus
  does (`0666 & ~umask` for files, `0777 & ~umask` for folders; with this machine's 002: files Read and Write / Read and
  Write / Read-Only, folders Create and Delete Files / Create and Delete Files / Access Files — exactly the recording).
  So an unchanged Change makes everything inside look freshly created. (*my call*, following the recording; the builder
  check pointed out the first draft's folder-based start isn't what Nautilus does.)
- **Change** applies to everything inside the folder (recursively, symlinks never followed or changed), files and folders
  separately, with symbolic modes so executables stay executable (Read-Only → `+r,-w`; folders Access Files → `+rx,-w`).
  Items you don't own are skipped and counted. Toast: "Changed permissions of 1,204 items" (+ ", 3 skipped").
- This is the one bulk action in Properties; the explicit Change button is its confirmation (as in Nautilus).

### Open With page ("Open With")

One boxed group, a row per app (icon, name); the default has a check at the right; clicking another row makes it the
default (same writer and toast as now).

### Details page (e.g. "Image Details")

One boxed group of property rows (dim title above the value, selectable) from `ops.sh meta`, as now.

### Dropdowns

A popover anchored under the row's value: Glass, radius 12, a row per choice with a check on the current one; Group's
popover adds a search field and scrolls (max 8 rows visible). Esc or a click outside closes the popover first, then the
page, then the card. Choosing applies at once (the queue against racing clicks stays).

### Motion

Pages slide: the new page comes from the right (x +40 → 0, fade in, `spatial`), back slides it out to the right; the
card's height follows the page (*my call*: no height animation, it jumps, per the motion spec's rule). Popovers scale
0.94 → 1 + fade (`fastSpatial`). The spinner turns only while counting / changing. Nothing animates with animations off.

## Keys

Esc closes the popover, else goes back a page, else closes the card. Alt+Left / Backspace (not while renaming) goes back
a page. Ctrl+Tab no longer applies (no tabs).

## Testing

- `ops.sh selftest`: `chgrp` to a group you're in (and refusing a link); `chmodtree DIR FILESYM DIRSYM` changes files and
  folders inside separately, keeps an executable's x, leaves a symlink and its target alone, prints `changed skipped`.
- `selftest.qml`: owner levels exclude None; umask → Enclosed start levels (002 and 022); the symbolic mode text for
  each level and class.
- Visual (headless captures, 1300 px and 500 px): main page for a photo, a folder (spinner, then done), several items;
  Permissions page for a file and a folder; the Access popover open; Group popover with search; Enclosed page;
  Open With page; Details page; Trash item (no Permissions/Open With rows, no pencil).
- IPC: `propsPage(name)` replaces `propsTab` (`""` = main, "Permissions", "Enclosed", "Open With", "Details"),
  `propsState()` gains `page`, keeps the rest; `propsGroup(name)`, `propsEnclosed(json)` (levels per class/kind) and
  `propsEnclosedApply()` drive the new actions; Enclosed on a scratch tree changes modes as `stat` confirms.

## Out of scope

The star (Places), changing the owner (needs root), SELinux "Security Context" (Ubuntu shows "Unknown"), undo for the
enclosed change.
