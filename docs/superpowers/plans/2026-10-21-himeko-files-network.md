# Himeko Files Network Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect to servers through gvfs, browse them like folders, and keep them one click away (Network page, sidebar,
pins, history), as in Nautilus 50.

**Architecture:** gvfs does the networking and exposes mounts as FUSE folders under `$XDG_RUNTIME_DIR/gvfs`, which the
existing folder view lists. A new `network.py` helper (Python + Gio) mounts, unmounts, lists mounts and browses
`network:///`. Password prompts travel as JSON lines over its stdin/stdout. `places.py` gains the servers history and
bookmarks by address. A long-running `gio mount -o` tells `Fs` when mounts change. A new `NetworkPage.qml` and
`AuthDialog.qml` carry the UI.

**Tech Stack:** Quickshell (QML, Qt 6), Python 3 + `gi` (Gio/GLib), gvfs + gvfsd-fuse, bash.

**Spec:** `docs/superpowers/specs/2026-10-21-himeko-files-network-design.md`

## Global Constraints

- **Where things go:** app code lives in `~/.config/hypr/custom/himeko-files/`, and `cd ~/VHyprland-End4-pC && ./sync.sh`
  copies it.
- **Commits:**
  - After `sync.sh`, run `git reset -q` and `git add` only this plan's files (sync.sh stages everything).
  - Commit on `main` and push per task.
  - **No Co-Authored-By or AI attribution.**
- **No new dependencies.** No new polling: the only new long-running process is `gio mount -o`, and its event-burst
  debounce is a single-shot timer, not a poll.
- **Passwords** go only over the helper's stdin. Never put them in argv, env, logs or files. Tests use `"save":"never"`.
- **JSON lines** from `network.py` are `json.dumps(obj)` with the default separators, one object per line:
  - asks: `{"ask": "password", "title", "message", "user", "domain", "needUser", "needDomain", "needPassword", "anonymous", "canSave"}`
    and `{"ask": "question", "title", "message", "choices": [...]}`;
  - answers: `{"user", "domain", "password", "anonymous", "save": "never"|"session"|"permanently"}`, `{"choice": N}`
    or `{"cancel": true}`;
  - results: `{"path": FUSE, "uri": ADDRESS}`, `{"item": {"name", "target", "kind"}}`, `{"done": true}` or
    `{"error": MESSAGE}`.
- **Files:**
  - the servers history is `$HF_SERVERS` or `~/.local/share/gtk-4.0/servers` (XBEL);
  - the gvfs FUSE root is `$XDG_RUNTIME_DIR/gvfs`;
  - "network mounts" are every mount whose root scheme isn't `file`, `mtp`, `gphoto2` or `afc`.
- **"Remote"** means inside one of those mounts' FUSE roots. In a remote location: no thumbnails, no folder counts, no
  image sizes, and no Recent entries.
- **Copy (exact strings):**
  - Network page: "Network", "Connected", "Previous", "Available on Current Network", "Looking for computers…",
    "Nothing found on this network", "Server address", "Connect", "Server Addresses";
  - "Server addresses are made up of a protocol prefix and an address. Examples:" and
    `smb://gnome.org, ssh://192.168.0.1, ftp://[2001:db8::1]`;
  - "Available Protocols", with the rows AppleTalk `afp://`, File Transfer Protocol `ftp://` or `ftps://`, Network
    File System `nfs://`, Samba `smb://`, SSH File Transfer Protocol `sftp://` or `ssh://`, WebDAV `dav://` or
    `davs://`;
  - toasts: "Add a protocol, like smb:// or sftp://", "Connecting to “<host>”…", "“<name>” was disconnected";
  - menus: "Unmount", "Copy Address", "Remove", "Open in New Tab";
  - the password dialog: "Connect As", "Anonymous", "Registered User", "Username", "Domain", "Password",
    "Remember Password", "Forget Immediately", "Until Logout", "Forever", "Cancel";
  - busy unmount: "“<name>” is busy", "Unmount Anyway".
- **Icons:**

  | Protocol | Icon |
  |---|---|
  | smb | `folder_shared` |
  | sftp/ssh, ftp/ftps, nfs, afp | `dns` |
  | dav/davs | `cloud` |
  | mtp | `smartphone` |
  | gphoto2 | `photo_camera` |
  | computer | `computer` |
  | anything else | `lan` |
- **Text:** server- and file-derived text is `textFormat: Text.PlainText`.
- **Tests:**
  - `ops.sh` network checks run under `env XDG_RUNTIME_DIR=<tmp> dbus-run-session -- …`, so the env comes before
    dbus-run-session.
  - Visual tests run on the headless output against `testdav.py` on 127.0.0.1, with a scratch `XDG_CONFIG_HOME`,
    `HF_SERVERS`, `HF_RECENT` and `HF_STARRED`.
  - `done.sh` unmounts `dav://127.0.0.1:*`.
- **Suite:** `~/.config/hypr/custom/himeko-files/ops.sh selftest && qs -p ~/.config/hypr/custom/himeko-files/selftest.qml 2>&1 | grep -q 'selftest: 0 failures'`

## Review Focus

- **The server stops answering mid-browse** (network drop, sleep): the window keeps responding, and Unmount still
  works. Pinned in Task 6 Step 4.
- **Cancel or a wrong password, again and again:** the dialog comes back with gvfs' message; Cancel leaves no mount
  and no helper process behind. Pinned in Task 4 Step 4.
- **Server-provided names with markup or odd characters** (`<b>x`, `a b#1`, non-ASCII share names): shown literally
  in rows, crumbs and the path field, and the address round-trips. Pinned in Task 3 Step 1 and Task 6 Step 3.
- **A mount made or removed elsewhere** (Nautilus, `gio mount`, another window): the sidebar and the Network page
  follow within a second, and tabs inside a removed mount go to Network. Pinned in Task 7 Step 4.
- **Address oddities** (IPv6 `ftp://[::1]:2121/`, `user@host:port`, a trailing slash, a server without a share, a
  missing protocol): the right host, page or toast. Pinned in Task 3 Step 1 and Task 4 Step 5.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `…/places.py` | + `servers list/add/remove`; bookmarks matched by address | Modify |
| `…/network.py` | `mounts`, `mount`, `unmount`, `browse` (JSON-line dialogue) | Create |
| `…/testdav.py` | small writable WebDAV server with Basic auth, for tests | Create |
| `…/ops.sh` | dispatch `servers`, `net`; `paste` through `gio copy/move` for gvfs paths; selftest | Modify |
| `…/Fs.qml` | network rules, mount watcher, `netMounts`, connect/unmount/browse/servers wrappers, remote gates | Modify |
| `…/AuthDialog.qml` | password and question dialog | Create |
| `…/NetworkPage.qml` | the Network page (Connected, Previous, Available, address bar) | Create |
| `…/Tab.qml` | `network:` places, names and Up for mounts, no counts when remote | Modify |
| `…/Browser.qml` | open addresses, crumbs/path field for servers, page swap, Del on remote, disconnects, IPC | Modify |
| `…/Sidebar.qml` | Network → page, Connected group, network pins | Modify |
| `…/InfoPanel.qml`, `…/DetailsList.qml`, `…/Properties.qml` | locations shown as addresses | Modify |
| `…/himeko-files` | an address argument opens it | Modify |
| `…/selftest.qml` | rules | Modify |
| `tools/himeko-files/done.sh` | also unmounts test dav mounts | Modify |

(`…` = `~/.config/hypr/custom/himeko-files`)

---

### Task 1: Servers history and bookmarks by address (places.py)

**Interfaces — Produces:**
- `ops.sh servers list` gives one address per line, newest first. `servers add ADDRESS` moves an existing entry to
  the top. `servers remove ADDRESS`.
- `ops.sh bookmarks pin|unpin|rename|move` accept an address (`scheme://…`, not `file://`) wherever they take a PATH.
  Matching is by URI with one trailing slash stripped (except the root `scheme://host/`).

- [ ] **Step 1: Write failing checks** in `ops.sh selftest`, before `exit $fail`:

```bash
    # ---- network: servers history, bookmarks by address ----
    export HF_SERVERS=$t/servers XDG_CONFIG_HOME=$t/cfg2
    "$me" servers add "sftp://host/srv"; "$me" servers add "smb://nas/share"; "$me" servers add "sftp://host/srv"
    check "servers: re-adding moves it first, no duplicates" "$("$me" servers list | tr '\n' ' ')" "sftp://host/srv smb://nas/share "
    chmod 640 "$HF_SERVERS"; "$me" servers remove "smb://nas/share"
    check "servers: remove keeps the rest and the mode" "$("$me" servers list | tr '\n' ' ')$(stat -c %a "$HF_SERVERS")" "sftp://host/srv 640"
    check "servers: GLib reads it" "$(python3 -I -c 'from gi.repository import GLib; import sys; b=GLib.BookmarkFile(); b.load_from_file(sys.argv[1]); print(len(b.get_uris()))' "$HF_SERVERS")" "1"
    : >"$t/nb"; B=$t/cfg2/gtk-3.0/bookmarks
    "$me" bookmarks pin "sftp://host/srv/data"; "$me" bookmarks pin "$t/nb"; "$me" bookmarks pin "sftp://host/srv/data/"
    "$me" bookmarks rename "sftp://host/srv/data" "Data"; "$me" bookmarks move "sftp://host/srv/data" 1
    check "bookmarks by address (no trailing-slash duplicate)" "$(sed "s|$t|T|" "$B" | tr '\n' '|')" "file://T/nb|sftp://host/srv/data Data|"
    "$me" bookmarks unpin "sftp://host/srv/data"
    check "bookmarks unpin by address" "$(wc -l <"$B")" "1"
    unset HF_SERVERS XDG_CONFIG_HOME
```

- [ ] **Step 2: Run** `ops.sh selftest`. Expected: these checks FAIL (`servers` is unknown, and the address is treated as
  a relative path).
- [ ] **Step 3: Implement** in `places.py`: a `SERVERS` path; `servers list|add|remove` through `GLib.BookmarkFile`
  (`load_recent`/`save_recent`-style helpers, mode kept, under the existing lock); add sets the modified time to now and
  list sorts by it. `bookmarks` resolves its target with `uri_of()` for paths and keeps addresses as given (one trailing
  slash stripped unless the path is `/`); `find_pin` compares a file line's path, or an address line's URI. `ops.sh`:
  `servers)` dispatches to places.py.
- [ ] **Step 4: Run** `ops.sh selftest`. Expected: all ok.
- [ ] **Step 5: Commit** `"Himeko Files: servers history and network bookmarks"`, then push.

---

### Task 2: network.py, the test server, paste over gvfs

**Interfaces — Produces:**
- `ops.sh net mounts` prints `name  uri  path  canUnmount(1|0)`, one network mount per line.
- `ops.sh net mount ADDRESS` runs the JSON-line dialogue (Global Constraints) and ends with `{"path", "uri"}` (exit 0)
  or `{"error"}` (exit 1). It reads one answer line from stdin per ask. If the address is already mounted, the path comes
  at once.
- `ops.sh net unmount ADDRESS [--force]` exits 0 on success, 2 when gvfs says busy (`Gio.IOErrorEnum.BUSY`) with the
  message on stderr, and 1 for any other failure.
- `ops.sh net browse ADDRESS` prints `{"item": …}` lines, then `{"done": true}` or `{"error"}`. It uses the same
  dialogue, so a NAS can ask for a login before listing its shares.
  - For `network:///` it keeps a directory monitor open for up to 3 s after the first listing, printing late items.
  - `kind` is `computer` (target has no share path), `share` (smb share or mountable) or `folder`.
- `ops.sh net schemes` prints the URI schemes `Gio.Vfs.get_default()` supports, one per line.
- Test hook: env `HF_ASK_QUESTION=1` makes `mount` send `{"ask": "question", "title": "Test question", "message": "Is this a test?", "choices": ["Log In Anyway", "Cancel"]}`
  before mounting. Choice 1 or cancel aborts with `{"error": "Cancelled"}`.
- `testdav.py DIR PORT USER PASS` is a WebDAV server with Basic auth: OPTIONS, PROPFIND (depth 0/1), GET, PUT, MKCOL,
  DELETE and MOVE, stdlib only.
- `ops.sh paste` uses `gio copy`/`gio move SRC TARGET` when SRC or DEST is under `$XDG_RUNTIME_DIR/gvfs`. The output
  format is unchanged: one line per source.

- [ ] **Step 1: Write failing checks** in `ops.sh selftest`:

```bash
    # ---- network: a private session bus and gvfs, so test mounts never reach the user's windows ----
    if command -v dbus-run-session >/dev/null && [ -x /usr/libexec/gvfsd-dav ]; then
        mkdir -p "$t/rt" "$t/dav/sub"; chmod 700 "$t/rt"; echo hello >"$t/dav/a.txt"; echo up >"$t/up.txt"
        port=$((20000 + RANDOM % 20000))
        python3 -I "$(dirname -- "$0")/testdav.py" "$t/dav" "$port" tester secret & dav=$!; sleep 0.5
        env XDG_RUNTIME_DIR="$t/rt" dbus-run-session -- bash -c '
            me=$1 port=$2 t=$3 a="dav://127.0.0.1:$2"
            printf "%s\n" "{\"user\": \"tester\", \"password\": \"wrong\", \"save\": \"never\"}" \
                          "{\"user\": \"tester\", \"password\": \"secret\", \"save\": \"never\"}" | "$me" net mount "$a/sub" >"$t/m1"
            "$me" net mounts | cut -f2 >"$t/m2"
            p=$(tail -1 "$t/m1" | python3 -I -c "import json,sys; print(json.load(sys.stdin)[\"path\"])")
            ls "$p/.." >"$t/m3"; "$me" paste copy "$p" "$t/up.txt" >"$t/m4"
            echo "{\"choice\": 1}" | HF_ASK_QUESTION=1 "$me" net mount "$a/" >"$t/m5"
            "$me" net unmount "$a/"; "$me" net mounts | wc -l >"$t/m6"
            s=$(date +%s); "$me" net browse "dav://127.0.0.1:1/" </dev/null | tail -1 >"$t/m7"; echo $(( $(date +%s) - s )) >"$t/m8"
        ' _ "$me" "$port" "$t" 2>/dev/null
        kill $dav
        check "net mount: asks again after a wrong password" "$(grep -c '"ask": "password"' "$t/m1")" "2"
        check "net mount: prints the folder's FUSE path" "$(tail -1 "$t/m1" | grep -c "/gvfs/dav:host=127.0.0.1,port=$port,ssl=false/sub\"")" "1"
        check "net mounts: lists it" "$(cat "$t/m2")" "dav://127.0.0.1:$port/"
        check "net: the FUSE folder lists the server" "$(tr '\n' ' ' <"$t/m3")" "a.txt sub "
        check "paste: copies onto a server" "$(grep -c '/sub/up.txt$' "$t/m4")$(cat "$t/dav/sub/up.txt")" "1up"
        check "net mount: question, then cancel" "$(head -1 "$t/m5" | grep -c '"ask": "question"')$(tail -1 "$t/m5")" '1{"error": "Cancelled"}'
        check "net unmount: gone" "$(cat "$t/m6")" "0"
        check "net browse: unreachable fails fast with a message" "$(grep -c '"error"' "$t/m7")$(( $(cat "$t/m8") < 10 ))" "11"
    fi
```

- [ ] **Step 2: Run** `ops.sh selftest`. Expected: these FAIL (`net` is unknown). The paste check gives its verdict on
  `cp -a` over FUSE. If it passes before Step 3's paste change, ledger that `gio copy` is unneeded and skip that part.
- [ ] **Step 3: Implement** `testdav.py` and `network.py`:
  - `Gio.MountOperation` with `ask-password` and `ask-question` handlers.
    - Each prints one ask line and reads one answer line with `sys.stdin.readline()`; EOF counts as cancel.
    - Each answer sets the operation: username, password, domain, anonymous, `password_save`
      (`never`/`session`/`permanently` → `Gio.PasswordSave.NEVER/FOR_SESSION/PERMANENTLY`), choice.
    - Then it calls `reply(HANDLED)`, or `ABORTED` on cancel.
  - Title and message come from gvfs' text: the first line is the title, the rest the message.
  - Flags: `needUser = flags & NEED_USERNAME`, and likewise `needDomain`, `needPassword`, `anonymous`
    (`ANONYMOUS_SUPPORTED`) and `canSave` (`SAVING_SUPPORTED`).
  - `mount` uses `Gio.File.new_for_uri(a).mount_enclosing_volume`. `ALREADY_MOUNTED` counts as success.
  - `ops.sh`: `net) exec python3 -I "$(dirname -- "$0")/network.py" "$@"`. In `paste`, a gvfs-root test chooses
    `gio copy -p`/`gio move` for the copy itself.
- [ ] **Step 4: Run** `ops.sh selftest`. Expected: all ok, and nothing new under `/run/user/$(id -u)/gvfs`.
- [ ] **Step 5: Commit** `"Himeko Files: network helper (mount, browse, gvfs paste)"`, then push.

---

### Task 3: Fs: network rules, watcher, wrappers, remote gates

**Interfaces — Produces:**
- Pure rules (each takes the mounts list explicitly):
  - `Fs.netMountOf(path, mounts)` returns `{name, uri, path, canUnmount}` or `null`;
  - `Fs.netAddress(path, mounts)`;
  - `Fs.netCrumbs(path, mounts)` returns `[{label, path, icon}]`;
  - `Fs.netIcon(uri)`, `Fs.isAddress(text)`, `Fs.isServerAddress(uri)`, `Fs.netHost(uri)`, `Fs.netPinName(uri, label)`.
- State:
  - `Fs.gvfsRoot`;
  - `Fs.netMounts` (from `net mounts`, refreshed by a `gio mount -o` Process plus a 150 ms single-shot debounce);
  - `Fs.isRemote(path)`;
  - `Fs.displayPath(path)` (the address when remote, otherwise `~`-shortened);
  - signal `Fs.disconnected(var mount)` for each mount that left the list.
- Wrappers:
  - `Fs.connect(address, remember, cb(path))`, where `remember` adds the address to servers on success;
  - `Fs.browse(address, onItem(item), onDone(error))`;
  - `Fs.unmount(uri, force)`;
  - `Fs.serversList(cb(uris))`, `Fs.serverRemove(uri)`;
  - signal `Fs.netAsk(var req)`, where `req` is the ask object plus `reply(answer)`.
- Pins:
  - `Fs.pins` also holds network bookmarks as `{uri, path: "", label, name: netPinName(uri, label), network: true, exists: true}`.
  - `Fs.pin`/`unpin`/`renamePin`/`movePin`/`isPinned` take a path or an address.

- [ ] **Step 1: Write failing checks** in `selftest.qml`:

```js
        // ---- network rules ----
        const mts = [{ name: "share on nas", uri: "smb://nas/share/", path: "/run/user/1000/gvfs/smb-share:server=nas,share=share" },
                     { name: "127.0.0.1:18080", uri: "dav://127.0.0.1:18080/", path: "/run/user/1000/gvfs/dav:host=127.0.0.1,port=18080,ssl=false" }];
        check("netMountOf: inside", Fs.netMountOf(mts[0].path + "/docs/a b", mts).name, "share on nas");
        check("netMountOf: local", Fs.netMountOf("/home/u/docs", mts), null);
        check("netMountOf: a longer name isn't inside", Fs.netMountOf(mts[0].path + "X", mts), null);
        check("netAddress: encodes the rest", Fs.netAddress(mts[0].path + "/docs/a b#1", mts), "smb://nas/share/docs/a%20b%231");
        check("netAddress: root", Fs.netAddress(mts[1].path, mts), "dav://127.0.0.1:18080/");
        check("netCrumbs", Fs.netCrumbs(mts[0].path + "/docs/<b>x", mts).map(c => c.label), ["share on nas", "docs", "<b>x"]);
        check("netIcon", ["smb://a/b", "sftp://h/", "ssh://h", "ftp://h", "davs://h", "mtp://p", "nfs://h/x", "zzz://h"].map(u => Fs.netIcon(u)),
              ["folder_shared", "dns", "dns", "dns", "cloud", "smartphone", "dns", "lan"]);
        check("isAddress", ["smb://nas", "nas", "/home/u", "file:///x", "ftp://[::1]:2121/"].map(u => Fs.isAddress(u)), [true, false, false, false, true]);
        check("isServerAddress", ["smb://nas", "smb://nas/", "smb://nas/share", "sftp://host/"].map(u => Fs.isServerAddress(u)), [true, true, false, false]);
        check("netHost", ["sftp://me@host:2222/srv", "ftp://[2001:db8::1]/", "smb://nas/share"].map(u => Fs.netHost(u)), ["host", "2001:db8::1", "nas"]);
        check("netPinName", [Fs.netPinName("sftp://host/srv/data", ""), Fs.netPinName("sftp://host/", ""), Fs.netPinName("smb://nas/share", "Office"),
              Fs.netPinName("smb://nas/My%20Docs", "")], ["data on host", "host", "Office", "My Docs on nas"]);
```

- [ ] **Step 2: Run** `selftest.qml`. Expected: FAIL (`netMountOf` is not a function).
- [ ] **Step 3: Implement** in `Fs.qml`:
  - **Rules and state** as listed.
  - **The dialogue Process:** `stdinEnabled: true`, with a `SplitParser` that parses each line. An ask emits `netAsk`
    with `reply(a)`, which writes `JSON.stringify(a) + "\n"`.
  - **Remote gates:**
    - `canThumb` returns false when `isRemote(item.path)`;
    - `details` skips `magick identify` when remote;
    - `recentAdd` skips remote paths;
    - `Tab.reload` skips `countSubfolders` when `Fs.isRemote(path)`.
  - **Pins:** `parseBookmarks` keeps addresses (`path: ""`); `checkPins` keeps network pins with `exists: true`.
- [ ] **Step 4: Run** the suite. Expected: green.
- [ ] **Step 5: Commit** `"Himeko Files: network state, rules and remote gates"`, then push.

---

### Task 4: Password/question dialog and opening addresses

**Files:** Create `AuthDialog.qml`. Modify `Browser.qml`, `himeko-files`, `shell.qml`.

**Interfaces:**
- `Browser.openAddress(text, remember = false)`:
  - no `://` gives the toast "Add a protocol, like smb:// or sftp://";
  - `Fs.isServerAddress` goes to `"network:" + address`;
  - otherwise it toasts "Connecting to “<host>”…", calls `Fs.connect(address, remember, path => tab.go(path))`, and
    opens the folder.
- The path field and `goTo` send addresses to `openAddress`. The launcher passes an address as `HF_ADDRESS`, which
  `openAddress` opens at start.
- IPC: `address(text)` calls `openAddress`; `authState()` returns JSON of what the dialog shows; `authFill(json)`
  fills the fields; `authAnswer(button)` presses "Connect"/"Cancel" or a choice label.

- [ ] **Step 1: AuthDialog**, in GNOME's layout (see the spec): title, message, then boxed rows shown as the flags ask.
  - **Connect As:** a segmented Anonymous / Registered User control, only when `anonymous`.
  - **Fields:** Username, Domain and Password (masked).
  - **Remember Password:** a dropdown with Forget Immediately (default) / Until Logout / Forever, only when `canSave`.
  - **Buttons:** Cancel / Connect. Enter connects, Esc cancels.
  - **Question mode:** the message, plus one button per choice.
  - **Plain text** for every string.
  - **Fields are cleared** after each reply.
  - **Busy unmount** reuses the question mode with "“<name>” is busy" and Unmount Anyway / Cancel.
- [ ] **Step 2: Wire** `Fs.netAsk` to the dialog, then `openAddress`, the path field, `HF_ADDRESS` (`himeko-files`: an
  argument matching `^[a-z][a-z0-9+.-]*://` that isn't `file://` sets `HF_ADDRESS` and opens Home under it).
- [ ] **Step 3: Check**, headless, with `testdav.py` on a free port and the scratch env:
  - `address dav://127.0.0.1:P/` brings up the dialog (capture it: no Connect As, no Domain).
  - `authFill` with a wrong password and Connect brings the dialog back with gvfs' message (capture).
  - The right password opens the folder.
  - `HF_ASK_QUESTION=1` shows the question dialog (capture).
  - Launching `himeko-files dav://127.0.0.1:P/sub` opens `sub`.
- [ ] **Step 4: Review focus: cancel loops.** Cancel three times in a row; no mount is left in `ops.sh net mounts`, and
  no `network.py` process is left (`pgrep -f network.py` by its PID list, never a pattern that matches your shell).
- [ ] **Step 5: Review focus: addresses.** `address nas` gives the protocol toast. `address smb://127.0.0.1` gives the
  Network page titled "127.0.0.1". `address ftp://[::1]:1/` gives the toast "Connecting to “::1”…", then gvfs' error
  toast.
- [ ] **Step 6: Run the suite.** Commit `"Himeko Files: connect dialog and network addresses"`, then push.

---

### Task 5: The Network page

**Files:** Create `NetworkPage.qml`. Modify `Tab.qml`, `Browser.qml`.

**Interfaces:**
- `Tab.place === "network"` for `"network:"` and for `"network:" + address` (a computer's shares).
  - `Tab.name` is "Network" or `Fs.netHost(address)`.
  - Tab skips listing and counts there.
- `Browser` shows `NetworkPage { tab }` instead of the icon or details view. F5 calls `page.refresh()`.
- IPC: `netRows()` returns JSON `[{section, name, address}]` for checks.

- [ ] **Step 1: NetworkPage**, as boxed lists in Himeko glass:
  - **Connected:** `Fs.netMounts`. Rows show the icon, the name, the dim address and an eject button. Click goes to
    `path`. The menu has Open, Open in New Tab, Copy Address and Unmount.
  - **Previous:** `Fs.serversList` minus connected. Click runs `openAddress(uri)` with `remember`. The menu has Connect,
    Copy Address and Remove.
  - **Available on Current Network:** `Fs.browse("network:///")` (or the tab's computer address). It shows "Looking
    for computers…" while running and "Nothing found on this network" when empty. `computer` opens `"network:" + target`;
    `share`/`folder` runs `openAddress(target)`.
  - **Address bar** at the bottom: the field ("Server address"), Connect (enabled when not empty), and an info button
    with a popover holding the spec's text and protocols. Only schemes in `Gio.Vfs` supported schemes are shown
    (`ops.sh net schemes`, called once). Connect and Enter run `openAddress(text, remember = true)`.
- [ ] **Step 2: Check**, headless, 1300 and 500 px:
  - With one dev mount connected and two scratch history entries (one of them connected), capture the page.
  - Remove a Previous entry and check `servers list`.
  - Open the info popover (capture).
  - Use the `smb://127.0.0.1` computer page with no shares: "Nothing found on this network".
- [ ] **Step 3: Run the suite.** Commit `"Himeko Files: Network page"`, then push.

---

### Task 6: Browsing a server

**Files:** Modify `Browser.qml`, `Tab.qml`, `InfoPanel.qml`, `DetailsList.qml`, `Properties.qml`, `Fs.qml`.

- [ ] **Step 1:** Crumbs use `Fs.netCrumbs` when remote.
  - The path field shows `Fs.netAddress`.
  - `Tab.name` at a mount root is the mount name.
  - `goUp` at a mount root goes to `"network:"`.
  - Locations in the info panel, the Location column and Properties' Parent Folder use `Fs.displayPath`.
  - Del on remote opens `confirmDelete()`.
  - Undo of a copy onto a remote folder deletes the copies (`rm -rf`) instead of trashing.
  - `Fs.disconnected(m)` moves every tab inside `m.path` to `"network:"` and toasts "“<name>” was disconnected".
- [ ] **Step 2: Check**, headless, against a writable dev mount:
  - Crumbs and the path field show the address (capture).
  - No thumbnails for `photo.png` copied onto the server (`samples.sh` files): the plain icon (capture).
  - New Folder, rename and paste a local file work (check the dev folder on disk).
  - Del asks "Delete 1 item forever?" (capture).
- [ ] **Step 3: Review focus: odd names.** Make a dev folder named `<b>x a#1`. Its crumb, tile and path field show it
  literally, and the path field reads `…/%3Cb%3Ex%20a%231`.
- [ ] **Step 4: Review focus: stalled server.** `kill -STOP` the dev server, then press F5 and open a subfolder. IPC
  `scrollY` still answers within 1 s and a capture succeeds. `kill -CONT`, then Unmount works.
- [ ] **Step 5: Run the suite.** Commit `"Himeko Files: browsing servers"`, then push.

---

### Task 7: Sidebar and network pins

**Files:** Modify `Sidebar.qml`, `Browser.qml`.

- [ ] **Step 1:** The Network row goes to `"network:"`, with Dolphin removed.
  - **Connected group:** after Devices, a "Connected" section label and one row per `Fs.netMounts` entry (icon, name,
    eject → `Fs.unmount(uri)`), active while inside it.
  - **Network pins:** a network icon, `name`, never dimmed; a click calls `openAddress(pin.uri)`. The pin menu and IPC
    pin functions take `pin.path || pin.uri`.
  - **Pinning:** Ctrl+D and the menus pin `Fs.netAddress(path)` when remote.
- [ ] **Step 2: Check** (1300 and 500 px):
  - The Connected group with eject (capture).
  - Ctrl+D in a dev subfolder writes `dav://127.0.0.1:P/sub` to the scratch bookmarks.
  - Unmount, then click the pin: the dialog, then the folder.
- [ ] **Step 3:** Unmounting through the eject button while a tab is inside moves the tab to Network, with the toast.
  Then hold a file open on the mount (`exec 3<"$fuse/a.txt"`) and eject:
  - If gvfs reports busy (exit 2), the "“<name>” is busy" question appears (capture), and Unmount Anyway unmounts.
  - If gvfs unmounts anyway, ledger that the busy path couldn't be exercised.
- [ ] **Step 4: Review focus: elsewhere.** `gio mount` of a second dev server from the shell shows in the sidebar and
  on the Network page within 1 s. `gio mount -u` from the shell removes it, and a tab inside goes to Network within
  1 s.
- [ ] **Step 5: Run the suite.** Commit `"Himeko Files: connected servers and network pins in the sidebar"`, then push.

---

### Task 8: Finish

- [ ] **Step 1: Perf** on `~/Pictures/Wallpapers`, twice:
  - RSS and idle CPU within noise of the Places numbers (262–266 MB, 0.1–0.2 %);
  - app children per idle minute unchanged (8), plus exactly one `gio mount -o` child.
- [ ] **Step 2: README** Himeko Files bullet: `- **Network**: connect to smb/sftp/ftp/WebDAV/NFS servers (passwords in the keyring), browse them like folders, see them in the sidebar, and pin server folders (shared with GNOME Files).`
  Remove "network places" from "Not there yet".
- [ ] **Step 3: `done.sh`** also runs `gio mount -u` for every `dav://127.0.0.1:*` mount. Run the suite, check the real
  bookmarks, recent and servers are untouched, and confirm no dev mounts are left. Commit `"Himeko Files: network finished"`
  with the perf lines, then push.
