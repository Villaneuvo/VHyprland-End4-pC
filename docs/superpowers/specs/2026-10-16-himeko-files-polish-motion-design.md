# Himeko Files: Polish & motion

Sub-project 1 of 6 in making Himeko Files the daily file manager (then Previews, Properties, Places,
Network, Drag & drop). Code: `home/.config/hypr/custom/himeko-files/` (live copy in `~/.config/hypr/custom/himeko-files/`).

## Goal

Make the app feel finished and alive without making it heavier: expressive motion that matches the
end4-pC shell, no content colliding with the floating chrome, a layout that holds up in narrow windows,
and the small information Nautilus shows (item counts, friendly dates).

**Success means**

- Every interaction in the motion catalog below animates with end4-pC's curves, and nothing animates
  when animations are off system-wide.
- Scrolled content never reads through the toolbar or tabs (the "logs Folder" / "17" collisions are gone).
- At 500 px wide nothing overlaps or gets cut mid-word: breadcrumbs, header and toolbar collapse.
- Folder tiles and the Details "Size" column show item counts; dates read like Nautilus.
- Idle CPU stays at 0 %, and memory does not grow (it should drop: see Thumbnails).

## Approach

Motion tokens in `Theme.qml`, copied from end4-pC's `Appearance.qml` (the app can't import the shell's
modules, and shouldn't break when end4-pC updates). Each component gets its own small `Behavior` or
transition. Only `opacity`, `scale` and `x`/`y` are animated, never sizes that make layouts recompute every
frame. Rejected: a central state machine in `Browser.qml` (makes the biggest file bigger) and importing
end4-pC's `Appearance` (not possible from a `qs -p` app, fragile).

## Motion tokens (`Theme.qml`)

| Token | Curve (bezier) | Duration |
|---|---|---|
| `fastSpatial` | expressiveFastSpatial `0.42, 1.67, 0.21, 0.90` (overshoot) | 350 ms |
| `spatial` | expressiveDefaultSpatial `0.38, 1.21, 0.22, 1.00` | 500 ms |
| `effects` | expressiveEffects `0.34, 0.80, 0.34, 1.00` | 200 ms |
| `enter` | emphasizedDecel `0.05, 0.7, 0.1, 1` | 400 ms |

`Theme.animate` is false when `gsettings org.gnome.desktop.interface enable-animations` is false or
Hyprland's `animations:enabled` is 0 (read once at startup). Every duration is `animate ? d : 0`.

## Motion catalog

| Interaction | Motion | Token | Where |
|---|---|---|---|
| Open a folder / Back / Forward | Content and large title fade in while sliding 12 px from the right (forward) or left (back) | `effects`, 250 ms | `Browser.qml` (`Tab.go()` records the direction) |
| Tiles appearing after a folder loads | The visible tiles fade in and rise 8 px, staggered 15 ms, at most the first 24 | `enter` | `ItemTile.qml` |
| Selecting | The cookie check scales 0 → 1 with overshoot; the accent ring fades in | `fastSpatial` / `effects` | `ItemTile.qml`, `DetailsList.qml` |
| Sidebar place | One highlight pill glides to the new place instead of jumping | `fastSpatial` | `Sidebar.qml` |
| Search | The breadcrumb capsule crossfades to the search field; the accent border fades in | `effects` | `Browser.qml` |
| Context menu | Scales 0.92 → 1 and fades in from the click point (transform origin = pointer); submenu slides in 8 px | `fastSpatial` | `Menu.qml`, `Browser.qml` |
| Toast | Rises 16 px and fades in; fades out | `enter` / `effects` | `Browser.qml` |
| Info panel | Slides in from the right (x offset + opacity); the file view takes its new width at once | `spatial` | `Browser.qml`, `InfoPanel.qml` |
| Icons ↔ Details | Crossfade | `effects` | `Browser.qml` |
| Tabs | A new pill scales up from 0.8; the active glass pill glides between tabs | `fastSpatial` | `Browser.qml` |
| Hovering a tile | Scale 1.02 | `effects` | `ItemTile.qml` |

Column counts in the icons view follow the width through a 100 ms debounce, so a resize or the info
panel sliding in does not rebuild the grid every frame (tiles stretch until it settles).

## Scroll edge effect

A gradient band from the main panel's top edge down to 60 px below the tabs: the content background
color at 95 % fading to transparent. It sits above the file view and below the glass capsules, so content
fades out before it passes under the chrome. Like iOS it only shows once content scrolls under the chrome:
its opacity follows the scroll offset (0 at rest, full after 40 px), so the large title is never dimmed.
No animation of its own: a binding on the scroll position.

## Narrow windows

- **Breadcrumbs**: when they don't fit, show the first crumb, a "…" button, and the last two. "…" opens a
  menu of the hidden levels.
Widths below are the main panel's (the area right of the sidebar).

- **Header** under 760 px: the filter chips become one filter button (menu with All/Images/Videos/Docs,
  the active one checked); the sort button drops its label.
- **Toolbar** under 640 px: the Icons/Details pair becomes a single toggle button.

## Item counts and dates

- **Folder item counts** ("24 items", "1 item", "Empty") on folder tiles and in the Details "Size" column.
  One process per folder visit counts every subfolder at once:
  `find DIR -mindepth 2 -maxdepth 2 -not -name '.*' -printf '%h\n'`, tallied in JS; subfolders it
  doesn't list are empty. Results are cached per folder; hidden entries are not counted. Shown as
  "Folder" while counting. The count runs with a 3 s timeout; if it runs out (huge trees such as
  `node_modules`), the folders keep showing "Folder".
- **Relative dates** (`Fs.date()`): "Just now" (< 1 min), "N min ago" (< 1 h), "Today, HH:MM",
  "Yesterday, HH:MM", "N days ago" (< 7 days), then "12 Oct", or "12 Oct 2025" for other years.
  Future dates (clock skew) show the absolute date.

## Thumbnails (memory)

Thumbnails are decoded at the size they are shown, rounded up to 128 or 256 px so zooming doesn't reload
them constantly (now always 256 px). The cache files stay 256 px (freedesktop "large").

## Testing

- `qs -p` self-check for the pure logic: relative dates (each bucket, year boundary, future) and the
  item-count tally (nested paths, empty folders).
- Visual checks through the existing IPC (`files go/select/menu/info/view`) and the offscreen window
  capture, at 1892 px and 500 px wide.
- Performance: RSS and CPU of the app on `~/Pictures/Wallpapers` and on a 3 915-file folder, before and
  after. Idle CPU sampled over 10 s must stay at 0 %; RSS must not be higher than before.

## Out of scope

Previews/Quick Look, Properties, Recent/pinned places, network, drag and drop: later sub-projects.
