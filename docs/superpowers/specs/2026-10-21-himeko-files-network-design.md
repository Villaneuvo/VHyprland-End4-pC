# Himeko Files: Network (connect to servers and browse them)

Sub-project 5 of 6 (after Polish & motion, Previews, Properties, Places; then Drag & drop). Code:
`home/.config/hypr/custom/himeko-files/` (live copy in `~/.config/hypr/custom/himeko-files/`).

The user skips question rounds for this roadmap; the calls below are mine, marked *my call* where they go beyond
GNOME Files, which is the reference for layout and behaviour (the user's chosen design model). Nautilus 50 is installed
here and is the version followed.

## Goal

Reach the files on other computers (a NAS, an office share, a server you SSH into) from Himeko Files itself: type an
address once, log in, and from then on the server is a click away, browsed like any folder. Today the sidebar's
Network row opens Dolphin.

**Success means**

- **Network** in the sidebar opens a Network page in Himeko Files laid out like Nautilus 50: **Connected**,
  **Previous**, **Available on Current Network**, and an address bar at the bottom (**Server address** field,
  **Connect**, and an info button that explains addresses).
- Connecting works for every protocol gvfs has here (smb, sftp/ssh, ftp/ftps, dav/davs, nfs, afp), asks for a password
  when the server wants one (with "remember" choices, stored by gvfs in the keyring), and answers gvfs' questions
  (e.g. an unknown SSH host key) with its own choices.
- A connected server is browsed like a local folder: breadcrumbs start with the server's name, the path field shows
  its address (`sftp://host/path`), files open in their apps, and copy/move/rename/new folder work.
- Connected servers are listed in the sidebar with an eject button; disconnecting from anywhere sends tabs that were
  inside it back to the Network page.
- A server folder can be pinned (Ctrl+D) as a GTK bookmark holding its network address, so Nautilus and GTK dialogs
  see it too; clicking that pin reconnects (asking for the password if needed) and opens it. Network bookmarks already
  in the file (`sftp://…`) show up as pins.

## Anti-goals

- A password on a command line, in the environment, in a log or on disk by us. It travels only over the helper's
  stdin; remembering it is gvfs' job (gnome-keyring is running here).
- A frozen window while a server is slow or unreachable.
- Downloading remote files just to draw thumbnails, count folder items or read image sizes.
- Corrupting the files shared with Nautilus (GTK bookmarks, the servers history).

## How it works (my calls)

- **gvfs does the networking; Himeko browses its FUSE view.** `gvfsd-fuse` is running and exposes every mount under
  `$XDG_RUNTIME_DIR/gvfs/` (e.g. `…/gvfs/dav:host=127.0.0.1,port=18080,ssl=false`). The folder view lists those
  paths like local ones. GIO maps a FUSE path back to its address (`Gio.File.new_for_path(p).get_uri()` gives
  `dav://127.0.0.1:18080/sub`), and an address to its FUSE path (`get_path()`). A spike on this machine confirmed both.
- **A small helper, `network.py`** (Python + Gio, like `places.py`), dispatched by `ops.sh`:
  - `mounts`: the connected network mounts. Name, root address, FUSE root path, can-unmount, one per line, TAB-separated.
    That is every mount whose root isn't `file://`, minus phones and cameras (`mtp`, `gphoto2`, `afc`). Those are
    devices, not servers, and are out of scope here (*my call*, builder check).
  - `mount ADDRESS`: connects to the location's enclosing mount and prints its FUSE path. It is a dialogue of JSON
    lines on stdin/stdout: gvfs' `ask-password` and `ask-question` go out as one line each, and the app answers with
    one line. Answering "cancel" aborts. Already connected: it prints the path at once.
  - `unmount ADDRESS [--force]`.
  - `browse ADDRESS`: the children of `network:///` (or of a server found there, e.g. `smb://nas/` listing its shares).
    Each child is a name, its target address and its kind (computer, share or folder).
    - It speaks the same password dialogue as `mount`, because a NAS may want a login to list its shares.
    - For `network:///` it prints what is there, then keeps watching for up to 3 s while the discovery daemons fill in.
      Then it exits.
- **The servers history** is Nautilus' own: `~/.local/share/gtk-4.0/servers` (an XBEL file; Nautilus 50 and GTK4
  read it). `places.py servers list|add|remove` uses the same atomic write, mode keeping and lock as Recent. A server
  connected from the address bar or the Previous list is added. **Remove** in the Previous row menu deletes it.
- **Mount changes arrive by watching, not polling.** One long-running `gio mount -o` (C, idle) prints when anything
  is mounted or unmounted, by us, Nautilus or anyone. Each burst triggers one `network.py mounts`.
  `$XDG_RUNTIME_DIR/gvfs` paths are known from that list.

## Network page

A page in the main area (tab title "Network", one crumb with the network icon, Back/Forward work), laid out as boxed
lists in Himeko glass:

- **Connected**: one row per mount. Icon by protocol, the gvfs name (e.g. "share on nas"), the address dimmed
  below, and an eject button (**Unmount**). Click opens it. Right-click: **Open**, **Open in New Tab**,
  **Copy Address**, **Unmount**.
- **Previous**: history entries that aren't connected now. Click reconnects. Right-click: **Connect**,
  **Copy Address**, **Remove**.
- **Available on Current Network**: what `network:///` finds, listed once when the page opens. **F5** lists again.
  While listing: "Looking for computers…". Nothing found: "Nothing found on this network". A computer opens its own
  list of shares, using the same layout, with the computer's name as the title. A share connects.
- **Address bar** at the bottom: field "Server address", **Connect** (enabled when the field isn't empty; Enter
  works too), and an info button with a popover:
  - "Server Addresses"
  - "Server addresses are made up of a protocol prefix and an address. Examples:"
  - `smb://gnome.org, ssh://192.168.0.1, ftp://[2001:db8::1]`
  - an **Available Protocols** list: AppleTalk `afp://`, File Transfer Protocol `ftp://` or `ftps://`, Network File
    System `nfs://`, Samba `smb://`, SSH File Transfer Protocol `sftp://` or `ssh://`, WebDAV `dav://` or `davs://`.

  It shows only protocols gvfs supports here.
- An address without `://` gets the toast "Add a protocol, like smb:// or sftp://" (*my call*: no guessing between
  smb and sftp).
- While connecting: the toast "Connecting to “<host>”…". On success the folder opens. On failure, gvfs' message is
  shown as an error toast.
- The path field (Ctrl+L) accepts addresses too (`smb://nas/share/docs`). It connects and opens that folder.
  `himeko-files ADDRESS` from the launcher does the same: the desktop entry passes URIs, and today an `sftp://…` link
  opens Home.
- A server address without a share (`smb://nas`) opens that computer's share list, like a computer found on the
  network.

## Password and questions

A glass dialog over the window, in GNOME's layout:
- **Title and message:** the title is gvfs' first line ("Authentication Required") and the message is the rest.
- **Connect As** (only when gvfs allows anonymous): a segmented **Anonymous** / **Registered User**.
- **Fields** shown as gvfs' flags ask: **Username** (pre-filled from gvfs), **Domain**, **Password** (masked), each a
  boxed entry row.
- **Remember Password** (only when gvfs can save): a dropdown with **Forget Immediately** (default, as GTK does),
  **Until Logout** and **Forever**.
- **Buttons:** **Cancel** / **Connect**. Enter connects, Esc cancels.

A wrong password brings the dialog back with gvfs' new message.

Questions (an unknown host key, "Log In Anyway") show the message and one button per gvfs choice. All gvfs text is
plain text.

## Browsing a server

- **Breadcrumbs:** the first crumb is the server with its protocol icon, then the folders. The path field shows the
  address. **Up** from a server's top folder goes to the Network page.
- **Nothing is downloaded behind the user's back** (*my call*, GNOME's default "local files only").
  - "Remote" means inside one of the mounts `mounts` lists (phones and cameras are not among them).
  - In a remote location there are no thumbnails, no folder item counts, and no image sizes in the info panel.
  - Quick Look and Properties still work, because the user asked for them.
- **The window never waits on a stalled server.** Qt's folder listing runs in its own thread. The plan proves this
  with a stopped dev server (`kill -STOP`): the window keeps responding. If it doesn't, server folders are listed
  through a helper instead.
- **Changes on the server don't show up live** (FUSE has no inotify). **F5** reloads, as with most backends in Nautilus.
- **Delete:** most servers have no Trash. **Del** on a network location asks "Delete N items forever?" (the existing
  permanent-delete confirmation) instead of failing.
- **Copy and move to or from a server** go through `gio copy` / `gio move` with the target name `ops.sh` picked.
  `cp -a` stops on FUSE when it can't keep owners or modes.
- **Undo of a copy to a server** deletes the copies we made, because there is no Trash to move them to.
- **A busy unmount** asks with the question dialog: "“<name>” is busy", with **Unmount Anyway** / **Cancel**. Unmount
  Anyway runs `--force`.
- **Recent:** files opened from a server are not added, because the entry would point nowhere once disconnected
  (*my call*). Stars on network items are kept like a drive's.
- **Disconnects:** when a mount disappears, tabs inside it go to the Network page, with the toast
  "“<name>” was disconnected".

## Sidebar and pins

- **Network** opens the Network page. It is no longer Dolphin.
- **Connected servers** appear after Devices, in a group titled "Connected" when there is at least one. Each has its
  protocol icon, the gvfs name and an eject button. Its row is active while you're inside it.
- **Network pins.**
  - Network bookmark lines (`sftp://…`, `smb://…`) become pins with a network icon. Their label is the bookmark label,
    or the host and last folder.
  - They are never dimmed; we can't know without connecting.
  - Clicking one connects, using the dialog if needed, and opens it.
  - Pin, unpin, rename and move work on them through `places.py`, matched by address.
- **Pinning a server folder** (Ctrl+D, menus) writes its network address, not the FUSE path.

## Icons by protocol

| Protocol | Icon |
|---|---|
| smb | `folder_shared` |
| sftp/ssh, ftp/ftps, nfs, afp | `dns` |
| dav/davs | `cloud` |
| mtp | `smartphone` |
| gphoto2 | `photo_camera` |
| a computer found on the network | `computer` |
| anything else | `lan` |

## Constraints

- No new dependencies: Python 3 with `gi` (Gio), `gio` and gvfs are installed.
- No new polling. The only long-running process added is `gio mount -o`, which wakes only on mount events. Network
  discovery runs only when the Network page opens or is refreshed.
- Every network call runs in a helper process, so the window never waits on the network.
- File-derived and server-derived text (names, labels, messages, addresses) is plain text.
- Writes to `bookmarks` and `servers` go through `places.py`: temp file and rename, mode kept, the same lock.
- Tests run on the headless output only.
  - `ops.sh selftest`'s network checks run in a private session bus with their own gvfs and `XDG_RUNTIME_DIR`, so
    their test mounts never show up in the user's own windows. If gvfs can't run privately, they run in the real
    session and unmount at the end.
  - The visual tests use the real session. A dev-server mount may show briefly in the user's own Himeko window, and
    `done.sh` unmounts it.
- Helper tests use temp files and env overrides, never the real `bookmarks`, `servers` or keyring:
  - "Forget Immediately" in tests;
  - `HF_SERVERS` overrides the history path, like `HF_RECENT`.

## Testing

- **Dev server:** `tools/himeko-files/davserver.py DIR PORT USER PASS`, a ~60-line read-only WebDAV server (stdlib)
  with Basic auth. It drives gvfs' real password flow against `dav://127.0.0.1:PORT/`. The spike showed gvfs asks
  "Authentication Required / Enter password for “himeko”" with username, password and saving flags.
- **`ops.sh selftest`:**
  - servers list/add/remove (round trip, mode, keeps others);
  - `network.py mount` against the dev server: wrong password, then the right one through the JSON dialogue; it
    prints the FUSE path;
  - `mounts` lists it; `unmount` removes it;
  - `browse` of an unreachable address fails quickly with a message;
  - bookmarks pin/unpin/rename/move by address.
- **`selftest.qml`:** FUSE path → crumbs and address (and back), the icon by protocol, the address check (missing
  protocol), the network pin label.
- **Visual** (headless, 1300 px and 500 px):
  - Network page with Connected, Previous and the empty "Available";
  - the password dialog (anonymous hidden, domain hidden for dav), the wrong-password retry, and the question
    dialog (a scripted `ask-question`);
  - a server folder with crumbs, the path field showing the address, no thumbnails;
  - the sidebar's Connected group with eject;
  - a network pin reconnecting after an unmount;
  - unmounting from outside (`gio mount -u`) sends the tab to Network within a second.
- **Performance:** Wallpapers RSS and idle as before, plus one idle `gio mount -o` process. No new spawns while idle.

Protocols: everything goes through the same GIO calls, but only WebDAV (the dev server) is verified here. SMB, SFTP,
FTP, NFS and AFP ship as generic GIO and get checked on real servers when the user tries them (*my call*: nothing
serves them on this machine, and adding a server would be a new dependency).

## Out of scope

- Progress and conflicts for copies to and from servers (sub-project 6).
- Online accounts (OneDrive, Google via GOA).
- Sharing your own folders.
- Live change notification from servers.
- Recent entries for remote files.
- Per-server settings.
- Replacing the 4 s `lsblk` poll with the mount watcher (possible later, noted).
- Phones and cameras (MTP/PTP): listing unmounted ones and mounting them on click (a later devices pass).
