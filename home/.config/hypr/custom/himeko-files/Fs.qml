pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Everything that touches the system: XDG folders, disks, mime types, apps, clipboard, file operations
// (through ops.sh, which never overwrites), undo and thumbnails.
Singleton {
    id: root
    readonly property string home: Quickshell.env("HOME")
    readonly property string here: home + "/.config/hypr/custom/himeko-files"
    readonly property string ops: here + "/ops.sh"
    readonly property string trashDir: home + "/.local/share/Trash/files"
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") + "/himeko-files"

    signal toast(string text, bool undoable)
    signal failed(string text)
    signal created(string path)          // new folder etc.: the view selects it and starts renaming

    // ---- run a command, get its stdout ----
    Component {
        id: procComp
        Process {
            property var cb
            stdout: StdioCollector { id: out }
            stderr: StdioCollector { id: err }
            onExited: (code) => { if (cb) cb(out.text, code, err.text); destroy(); }
        }
    }
    // ---- run a command, get its stdout line by line (stop it with running = false) ----
    Component {
        id: streamComp
        Process {
            property var cb
            stdout: SplitParser { onRead: (line) => cb(line) }
            onExited: destroy()
        }
    }
    function stream(cmd, cb) {
        const p = streamComp.createObject(root, { command: cmd, cb: cb });
        p.running = true;
        return p;
    }
    function run(cmd, cb) {
        const p = procComp.createObject(root, { command: cmd, cb: cb });
        p.running = true;
    }
    function lines(text) { return text.split("\n").filter(l => l.length > 0); }

    // ---- places ----
    property var dirs: ({ home: home })
    property var devices: []
    property string diskLine: ""
    property real diskUsed: 0
    property int trashCount: 0
    function refreshPlaces() {
        run(["bash", "-c", "for d in DESKTOP DOCUMENTS DOWNLOAD MUSIC PICTURES VIDEOS; do echo \"$d=$(xdg-user-dir $d)\"; done"], (text) => {
            const d = { home: root.home };
            for (const l of root.lines(text)) { const i = l.indexOf("="); d[l.slice(0, i).toLowerCase()] = l.slice(i + 1); }
            root.dirs = d;
        });
        run(["df", "-B1", "--output=size,avail", root.home], (text) => {
            const v = root.lines(text).pop().trim().split(/\s+/).map(Number);
            root.diskUsed = 1 - v[1] / v[0];
            root.diskLine = root.size(v[1]) + " free of " + root.size(v[0]);
        });
        run(["lsblk", "-J", "-b", "-o", "PATH,LABEL,SIZE,MOUNTPOINT,HOTPLUG,TYPE,FSTYPE"], (text) => {
            let list = [];
            try {
                const walk = (arr) => arr.forEach(b => {
                    if (b.hotplug && b.type === "part" && b.fstype)
                        list.push({ dev: b.path, label: b.label || root.size(b.size) + " drive", mount: b.mountpoint || "" });
                    if (b.children) walk(b.children);
                });
                walk(JSON.parse(text).blockdevices);
            } catch (e) {}
            if (JSON.stringify(list) !== JSON.stringify(root.devices)) root.devices = list;   // every 4 s: only real changes
        });
        run(["bash", "-c", "ls -A \"$1\" 2>/dev/null | wc -l", "_", root.trashDir], (text) => root.trashCount = Number(text.trim()) || 0);
    }
    Timer { interval: 4000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refreshPlaces() }

    // ---- Recent, Starred, pinned folders: places.py reads and writes the files, we watch them (no polling) ----
    readonly property string recentPath: "recent:"
    readonly property string starredPath: "starred:"
    readonly property string recentFile: Quickshell.env("HF_RECENT") || home + "/.local/share/recently-used.xbel"
    readonly property string starredFile: Quickshell.env("HF_STARRED") || home + "/.local/state/himeko-files/starred"
    readonly property string bookmarksFile: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/gtk-3.0/bookmarks"
    property var bookmarks: []           // GTK's bookmarks: [{ uri, path ("" for other schemes), label, name }]
    property var pins: []                // the folders among them, in order, + exists
    property var starred: ({})           // path -> true
    function isStarred(path) { return starred[path] === true; }
    function isPinned(target) {   // a path, or a network address
        const t = isAddress(target) ? normAddress(target) : target;
        return bookmarks.some(b => (b.path || normAddress(b.uri)) === t);
    }
    // A FileView can't watch a file whose folder doesn't exist yet (the first star creates ~/.local/state/himeko-files)
    property bool placesWatching: false
    FileView {
        path: root.placesWatching ? root.bookmarksFile : ""; watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: root.bookmarks = root.parseBookmarks(text())
        onLoadFailed: root.bookmarks = []
    }
    FileView {
        path: root.placesWatching ? root.starredFile : ""; watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: { const m = {}; for (const p of root.lines(text())) m[p] = true; root.starred = m; }
        onLoadFailed: root.starred = {}
    }
    onBookmarksChanged: checkPins()
    onDevicesChanged: checkPins()           // a pinned folder on a drive comes and goes with it
    function parseBookmarks(text) {
        return lines(text).filter(l => l.trim()).map(l => {
            const i = l.indexOf(" "), uri = i < 0 ? l : l.slice(0, i), label = i < 0 ? "" : l.slice(i + 1);
            let path = "";
            if (uri.startsWith("file:///")) try { path = decodeURIComponent(uri.slice(7)).replace(/(.)\/+$/, "$1"); } catch (e) {}
            return { uri: uri, path: path, label: label,
                     name: path ? label || path.slice(path.lastIndexOf("/") + 1) || uri : isAddress(uri) ? netPinName(uri, label) : label || uri };
        });
    }
    readonly property var pinIcons: ({ documents: "description", download: "download", music: "music_note",
                                       pictures: "image", videos: "movie", desktop: "desktop_windows" })
    function pinIcon(path, dirs) {
        for (const k in pinIcons) if (dirs[k] === path) return pinIcons[k];
        return "folder";
    }
    function openedText(d) { return "Opened " + date(d); }
    // Pins: local folders (checked on disk) and network addresses (never dimmed: we can't know without connecting).
    // `key` is what the pin menu and places.py use: the path, or the address
    function checkPins() {
        const bm = bookmarks, list = bm.filter(b => b.path || isAddress(b.uri)), local = list.filter(b => b.path);
        const done = (ok) => {
            if (root.bookmarks !== bm) return;   // changed meanwhile: that change asks again
            root.pins = list.map(b => Object.assign({ exists: !b.path || ok[local.indexOf(b)] === "1", network: !b.path, key: b.path || b.uri }, b));
        };
        if (!local.length) return done([]);
        run(["bash", "-c", "for p; do [ -d \"$p\" ] && echo 1 || echo 0; done", "_"].concat(local.map(b => b.path)), (text) => done(root.lines(text)));
    }
    // places.py lines (path, isDir, size, mtime[, used]) as items like Tab's
    function placeItems(text) {
        return lines(text).map(l => {
            const f = l.split("\t"), name = f[0].slice(f[0].lastIndexOf("/") + 1), dot = name.lastIndexOf(".");
            return { name: name, path: f[0], isDir: f[1] === "1", size: Number(f[2]), modified: new Date(f[3] * 1000),
                     suffix: dot > 0 ? name.slice(dot + 1) : "", used: f[4] ? new Date(f[4] * 1000) : null };
        });
    }
    function places(args, cb) {
        run([ops].concat(args), (t, code, err) => { if (code) failed(err.trim() || "Couldn't save the change"); else if (cb) cb(); });
    }
    function recentList(cb) { run([ops, "recent", "list"], (text) => cb(placeItems(text))); }
    function starredList(cb) { run([ops, "starred", "list"], (text) => cb(placeItems(text))); }
    function recentAdd(path) { if (!isRemote(path)) run([ops, "recent", "add", path], null); }   // a server's file would point nowhere later
    function recentRemove(paths, cb) { places(["recent", "remove"].concat(paths), cb); }
    function setStarred(paths, on) { places(["starred", on ? "add" : "remove"].concat(paths)); }
    function pin(path) { places(["bookmarks", "pin", path]); }
    function unpin(path) { places(["bookmarks", "unpin", path]); }
    function renamePin(path, label) { places(["bookmarks", "rename", path, label]); }
    function movePin(path, d) { places(["bookmarks", "move", path, String(d)]); }
    function placesMoved(pairs) { if (pairs.length) run([ops, "placesmoved"].concat(...pairs), null); }   // [[from, to]]
    // ops.sh paste prints one line per source (empty = skipped): [[src, created]] for the ones that happened
    function pastePairs(text, paths) { return text.split("\n").slice(0, paths.length).map((t, i) => [paths[i], t]).filter(p => p[1]); }

    // ---- network: gvfs mounts, browsed through gvfs' FUSE folder; network.py talks to gvfs ----
    readonly property string gvfsRoot: Quickshell.env("XDG_RUNTIME_DIR") + "/gvfs"
    property var netMounts: []           // [{ name, uri, path, canUnmount }]
    signal disconnected(var mount)       // a mount left (unmounted here, in Nautilus, or the server went away)
    signal netAsk(var req)               // gvfs asks (password, question): the ask object + reply(answer)
    function isRemote(path) { return netMountOf(path, netMounts) !== null; }
    function displayPath(path) { return isRemote(path) ? netAddress(path, netMounts) : path.replace(home, "~"); }
    function netMountOf(path, mounts) { return mounts.find(m => path === m.path || path.startsWith(m.path + "/")) ?? null; }
    function netAddress(path, mounts) {
        const m = netMountOf(path, mounts);
        if (!m) return "";
        return m.uri.replace(/\/$/, "") + "/" + path.slice(m.path.length).split("/").filter(s => s).map(s => encodeURIComponent(s)).join("/");
    }
    function netCrumbs(path, mounts) {
        const m = netMountOf(path, mounts);
        if (!m) return [];
        const out = [{ label: m.name, path: m.path, icon: netIcon(m.uri) }];
        let acc = m.path;
        for (const s of path.slice(m.path.length).split("/").filter(x => x)) { acc += "/" + s; out.push({ label: s, path: acc }); }
        return out;
    }
    readonly property var netIcons: ({ smb: "folder_shared", sftp: "dns", ssh: "dns", ftp: "dns", ftps: "dns", nfs: "dns", afp: "dns",
                                       dav: "cloud", davs: "cloud", mtp: "smartphone", gphoto2: "photo_camera" })
    function netIcon(uri) { return netIcons[uri.slice(0, Math.max(0, uri.indexOf(":"))).toLowerCase()] ?? "lan"; }
    function isAddress(text) { return /^[a-z][a-z0-9+.-]*:\/\//i.test(text) && !/^file:/i.test(text); }
    function isServerAddress(uri) { return /^smb:\/\/[^/]+\/?$/i.test(uri); }   // a computer: its shares are a list
    function netHost(uri) {
        const auth = uri.replace(/^[a-z][a-z0-9+.-]*:\/\//i, "").split("/")[0], hostport = auth.slice(auth.lastIndexOf("@") + 1);
        return hostport.startsWith("[") ? hostport.slice(1, hostport.indexOf("]")) : hostport.split(":")[0];
    }
    function netPinName(uri, label) {
        if (label) return label;
        const parts = uri.replace(/^[a-z][a-z0-9+.-]*:\/\/[^/]*/i, "").split("/").filter(s => s);
        let last = parts.length ? parts[parts.length - 1] : "";
        try { last = decodeURIComponent(last); } catch (e) {}
        return last ? last + " on " + netHost(uri) : netHost(uri);
    }
    // Same rule as places.py: an address without its trailing slashes, except a server's root
    function normAddress(u) {
        const m = /^([a-z][a-z0-9+.-]*:\/\/[^/]*)(\/.*)$/i.exec(u);
        return m ? m[1] + (m[2].replace(/\/+$/, "") || "/") : u;
    }

    // Mount changes come from `gio mount -o` (idle until something mounts); each burst lists the mounts once
    Process {
        running: true
        command: ["gio", "mount", "-o"]
        stdout: SplitParser { onRead: (line) => netBurst.restart() }
    }
    Timer { id: netBurst; interval: 150; onTriggered: root.refreshMounts() }
    function refreshMounts() {
        run([ops, "net", "mounts"], (text) => {
            const list = root.lines(text).map(l => { const f = l.split("\t"); return { name: f[0], uri: f[1], path: f[2], canUnmount: f[3] === "1" }; });
            const gone = root.netMounts.filter(m => !list.some(n => n.path === m.path));
            if (JSON.stringify(list) !== JSON.stringify(root.netMounts)) root.netMounts = list;
            gone.forEach(m => root.disconnected(m));
        });
    }

    // network.py's dialogue: asks go out through netAsk, the answer is written back on its stdin
    Component {
        id: talkComp
        Process {
            property var lineCb
            stdinEnabled: true
            stdout: SplitParser { onRead: (line) => lineCb(line) }
            onExited: destroy()
        }
    }
    function talk(args, onResult) {
        const p = talkComp.createObject(root, { command: [ops, "net"].concat(args) });
        p.lineCb = (line) => {
            let o;
            try { o = JSON.parse(line); } catch (e) { return; }
            if (o.ask) root.netAsk(Object.assign(o, { reply: (a) => p.write(JSON.stringify(a) + "\n") }));
            else onResult(o);
        };
        p.running = true;
        return p;
    }
    function connect(address, remember, cb) {
        talk(["mount", address], (o) => {
            if (o.path) {
                if (remember) places(["servers", "add", address]);
                refreshMounts();
                cb(o.path);
            } else if (o.error && o.error !== "Cancelled") failed(o.error);
        });
    }
    function browse(address, onItem, onDone) {
        return talk(["browse", address], (o) => o.item ? onItem(o.item) : onDone(o.error && o.error !== "Cancelled" ? o.error : ""));
    }
    function unmount(uri, force) {
        run([ops, "net", "unmount", uri].concat(force ? ["--force"] : []), (t, code, err) => {
            if (code === 2) {
                const m = root.netMounts.find(x => x.uri === uri);
                root.netAsk({ ask: "question", title: "“" + (m ? m.name : root.netHost(uri)) + "” is busy", message: err.trim(),
                              choices: ["Unmount Anyway", "Cancel"], reply: (a) => { if (a.choice === 0) root.unmount(uri, true); } });
            } else if (code) root.failed(err.trim() || "Couldn't unmount");
        });
    }
    function serversList(cb) { run([ops, "servers", "list"], (text) => cb(lines(text))); }
    function serverRemove(uri) { places(["servers", "remove", uri]); }

    function mount(dev, cb) { run(["udisksctl", "mount", "-b", dev], (t, code, e) => { root.refreshPlaces(); if (code) root.failed(e.trim()); else if (cb) cb(); }); }
    function eject(dev) { run(["bash", "-c", "udisksctl unmount -b \"$1\" && udisksctl power-off -b \"$1\"", "_", dev], (t, code, e) => { root.refreshPlaces(); if (code) root.failed(e.trim()); else root.toast("Safe to remove", false); }); }

    // ---- formatting / kinds ----
    function size(b) {
        if (b < 1024) return b + " B";
        const u = ["KB", "MB", "GB", "TB"]; let i = -1;
        do { b /= 1024; i++; } while (b >= 1024 && i < u.length - 1);
        return (b < 10 ? b.toFixed(1) : Math.round(b)) + " " + u[i];
    }
    // Nautilus-style: "Just now", "5 min ago", "Today, 14:39", "Yesterday, 16:28", "3 days ago",
    // "12 Oct", "12 Oct 2025". `now` is for the self-check.
    function date(d, now) {
        now = now ?? new Date();
        const t = d.getTime(), diff = now.getTime() - t, min = 60000, day = 86400000;
        const absolute = () => Qt.formatDate(d, d.getFullYear() === now.getFullYear() ? "d MMM" : "d MMM yyyy");
        if (diff < 0) return absolute();
        if (diff < min) return "Just now";
        if (diff < 60 * min) return Math.floor(diff / min) + " min ago";
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
        const thatDay = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
        const days = Math.round((today - thatDay) / day);   // calendar days, safe across DST
        const hm = Qt.formatTime(d, "hh:mm");
        if (days === 0) return "Today, " + hm;
        if (days === 1) return "Yesterday, " + hm;
        if (days < 7) return days + " days ago";
        return absolute();
    }

    // ---- folder item counts: one `find` per folder visit counts every subfolder at once ----
    // Subfolders find couldn't open ("find: '/a/it\'s': Permission denied") map to null: unknown, not empty.
    function tallyCounts(text, errText) {
        const counts = {};
        for (const l of lines(text)) counts[l] = (counts[l] ?? 0) + 1;
        for (const l of lines(errText ?? "")) {
            const m = l.match(/^find: '(.*)': Permission denied$/);
            if (m) counts[m[1].replace(/\\(.)/g, "$1")] = null;
        }
        return counts;
    }
    // Subfolders find didn't list are empty; null counts (not counted yet) and null entries mean unknown.
    function countOf(counts, p) { return counts ? (p in counts ? counts[p] : 0) : null; }
    // cb(counts) with { subfolderPath: visibleItemCount }; -L follows symlinked folders like the listing does.
    // cb(null) when it ran out of time (huge trees): callers keep showing "Folder".
    function countSubfolders(dir, cb) {
        run(["env", "LC_ALL=C", "timeout", "3", "find", "-L", dir, "-mindepth", "2", "-maxdepth", "2", "-not", "-name", ".*", "-printf", "%h\\n"],
            (text, code, err) => cb(code === 124 ? null : tallyCounts(text, err)));
    }
    // The same for a list of folders (Recent, Starred): their own items
    function countFolders(dirs, cb) {
        run(["env", "LC_ALL=C", "timeout", "3", "find", "-L"].concat(dirs, ["-mindepth", "1", "-maxdepth", "1", "-not", "-name", ".*", "-printf", "%h\\n"]),
            (text, code, err) => cb(code === 124 ? null : tallyCounts(text, err)));
    }
    function parentOf(path) { return path.slice(0, path.lastIndexOf("/")) || "/"; }
    function countLabel(n) {
        if (n == null) return "Folder";
        if (n === 0) return "Empty";
        return n === 1 ? "1 item" : n + " items";
    }
    readonly property var kinds: ({
        image: { icon: "image", label: "Image", ext: ["jpg", "jpeg", "png", "gif", "webp", "avif", "bmp", "svg", "heic", "jxl", "tif", "tiff", "ico"] },
        video: { icon: "movie", label: "Video", ext: ["mp4", "mkv", "webm", "mov", "avi", "m4v", "flv", "wmv", "mpg", "mpeg", "3gp", "ogv"] },
        audio: { icon: "music_note", label: "Audio", ext: ["mp3", "flac", "ogg", "opus", "wav", "m4a", "aac"] },
        pdf: { icon: "picture_as_pdf", label: "PDF", ext: ["pdf"] },
        doc: { icon: "description", label: "Document", ext: ["txt", "md", "doc", "docx", "odt", "rtf", "epub", "cbz", "cbr", "cb7", "cbt", "djvu"] },
        sheet: { icon: "table_chart", label: "Spreadsheet", ext: ["csv", "xls", "xlsx", "ods"] },
        slides: { icon: "slideshow", label: "Presentation", ext: ["ppt", "pptx", "odp"] },
        archive: { icon: "folder_zip", label: "Archive", ext: ["zip", "gz", "xz", "bz2", "zst", "tar", "7z", "rar", "tgz"] },
        code: { icon: "code", label: "Code", ext: ["js", "ts", "tsx", "jsx", "py", "sh", "lua", "qml", "json", "yml", "yaml", "toml", "html", "css", "c", "cpp", "h", "rs", "go", "java", "php", "sql", "conf", "ini", "xml"] },
        app: { icon: "deployed_code", label: "Application", ext: ["appimage", "deb", "exe", "desktop", "run"] },
        font: { icon: "font_download", label: "Font", ext: ["ttf", "otf", "woff", "woff2", "ttc"] },
        disk: { icon: "album", label: "Disk image", ext: ["iso", "img"] }
    })
    readonly property var extKind: {
        const m = {};
        for (const k in kinds) for (const e of kinds[k].ext) m[e] = k;
        return m;
    }
    function kindOf(item) { return item.isDir ? "folder" : (extKind[(item.suffix || "").toLowerCase()] ?? "file"); }
    function iconOf(kind) { return kind === "folder" ? "folder" : (kinds[kind]?.icon ?? "draft"); }
    function labelOf(kind, suffix) { return kind === "folder" ? "Folder" : (kinds[kind]?.label ?? ((suffix ? suffix.toUpperCase() + " " : "") + "file")); }
    function isArchive(item) { return kindOf(item) === "archive"; }
    // Quick Look body for an item: kinds that say enough map directly, the rest need the MIME type ("" until known)
    readonly property var textMimes: ["application/json", "application/xml", "application/x-shellscript", "application/javascript",
                                      "application/toml", "application/yaml", "application/x-yaml"]
    function previewType(kind, mime) {
        if (["image", "video", "audio", "pdf", "font", "folder"].indexOf(kind) >= 0) return kind;
        if (kind === "code") return "text";
        if (!mime) return "";
        if (mime.startsWith("text/") || textMimes.indexOf(mime) >= 0) return "text";
        if (mime.startsWith("video/")) return "video";
        if (mime.startsWith("audio/")) return "audio";
        return "info";
    }
    // PDF wheel: one page per notch (120); a touchpad's small deltas add up instead of flipping a page each
    function wheelStep(acc, dy) { const a = acc + dy, n = Math.trunc(a / 120); return { flip: -n + 0, acc: a - n * 120 + 0 }; }
    // ---- properties: permission levels as Nautilus words them, size and date text ----
    readonly property var fileLevels: ["None", "Read-Only", "Read and Write"]
    readonly property var dirLevels: ["None", "List Files Only", "Access Files", "Create and Delete Files"]
    readonly property var dirBits: ({ "None": 0, "List Files Only": 4, "Access Files": 5, "Create and Delete Files": 7 })
    readonly property var fileBits: ({ "None": 0, "Read-Only": 4, "Read and Write": 6 })
    readonly property var shiftOf: ({ u: 6, g: 3, o: 0 })
    function levels(isDir) { return isDir ? dirLevels : fileLevels; }
    // "" = a combination the levels don't name (shown as "Custom"); files ignore x (its own toggle)
    function accessOf(mode, who, isDir) {
        const b = (mode >> shiftOf[who]) & 7;
        if (isDir) return Object.keys(dirBits).find(k => dirBits[k] === b) ?? "";
        return Object.keys(fileBits).find(k => fileBits[k] === (b & 6)) ?? "";
    }
    // Only that class's bits change (setuid etc. kept); files keep the class's x
    function withAccess(mode, who, level, isDir) {
        const sh = shiftOf[who], bits = isDir ? dirBits[level] : fileBits[level] | ((mode >> sh) & 1);
        return (mode & ~(7 << sh)) | (bits << sh);
    }
    // Owner is never offered "None" (as in GNOME Files)
    function levelsFor(who, isDir) { return levels(isDir).filter(l => who !== "u" || l !== "None"); }
    // Enclosed-files start values: what new files and folders get (0666/0777 minus the umask), as GNOME Files does
    function umaskLevels(umask) {
        const f = 0o666 & ~umask, d = 0o777 & ~umask, of = (m, isDir) => ({ u: accessOf(m, "u", isDir), g: accessOf(m, "g", isDir), o: accessOf(m, "o", isDir) });
        return { files: of(f, false), folders: of(d, true) };
    }
    // chmod's symbolic form for one class: adds what the level has, removes what it lacks; files never touch x
    function symbolic(who, level, isDir) {
        const bits = isDir ? dirBits[level] : fileBits[level], all = isDir ? [["r", 4], ["w", 2], ["x", 1]] : [["r", 4], ["w", 2]];
        const add = all.filter(b => bits & b[1]).map(b => b[0]).join(""), del = all.filter(b => !(bits & b[1])).map(b => b[0]).join("");
        return [add ? who + "+" + add : "", del ? who + "-" + del : ""].filter(x => x).join(",");
    }
    function symbolicAll(levels, isDir) { return ["u", "g", "o"].map(w => symbolic(w, levels[w], isDir)).join(","); }
    function isExec(mode) { return (mode & 0o111) !== 0; }
    function withExec(mode, on) { return on ? mode | ((mode & 0o444) >> 2) : mode & ~0o111; }   // x where readable
    function shared(values) { return values.every(v => v === values[0]) ? values[0] : "Mixed"; }
    function sizeText(b) {
        const exact = String(b).replace(/\B(?=(\d{3})+(?!\d))/g, ",") + " bytes";
        return b < 1024 ? exact : size(b) + " (" + exact + ")";
    }
    readonly property var dayNames: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    readonly property var monthNames: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    function fullDate(d) {
        return dayNames[d.getDay()] + ", " + d.getDate() + " " + monthNames[d.getMonth()] + " " + d.getFullYear() + ", "
             + String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0");
    }
    // ops.sh props → [{ mode, owner, group, mine, size, atime, mtime, birth, type, target, mime, description, avail, total }]
    // (null for a path it couldn't read)
    function props(paths, cb) {
        run([ops, "props"].concat(paths), (text) => cb(text.split("\n").slice(0, paths.length).map(l => {
            if (l === "!" || !l) return null;
            const f = l.split("\t"), t = (s) => new Date(Number(s) * 1000);
            return { mode: parseInt(f[0], 8), owner: f[1], group: f[2], mine: f[3] === "1", size: Number(f[4]), atime: t(f[5]),
                     mtime: t(f[6]), birth: Number(f[7]) > 0 ? t(f[7]) : null, type: f[8], target: f[9], mime: f[10],
                     description: f[11], avail: Number(f[12] || 0), total: Number(f[13] || 0) };
        })));
    }
    // Live folder totals: cb(items, bytes, done) as ops.sh dirsize streams them; returns the Process (running = false stops)
    function dirSize(paths, cb) {
        return stream([ops, "dirsize"].concat(paths), (l) => {
            const f = l.split("\t");
            if (f[0] === "done") cb(Number(f[1]), Number(f[2]), true);
            else cb(Number(f[0]), Number(f[1]), false);
        });
    }
    function chmod(mode, paths, cb) {
        run([ops, "chmod", mode.toString(8)].concat(paths), (t, code, err) => {
            if (code) failed(err.trim() || "Couldn't change the permissions");
            if (cb) cb(code === 0);
        });
    }
    function meta(path, kind, cb) {
        run([ops, "meta", path, kind], (text) => cb(lines(text).map(l => { const i = l.indexOf("\t"); return [l.slice(0, i), l.slice(i + 1)]; })));
    }
    function chgrp(group, paths, cb) {
        run([ops, "chgrp", group].concat(paths), (t, code, err) => {
            if (code) failed(err.trim() || "Couldn't change the group");
            if (cb) cb(code === 0);
        });
    }
    // Symbolic modes for everything you own inside dir (never .ssh/.gnupg): cb(changed, skipped, unreachable)
    function chmodTree(dir, filesSym, dirsSym, cb) {
        run([ops, "chmodtree", dir, filesSym, dirsSym], (text) => {
            const f = text.trim().split("\t");
            cb(Number(f[0] || 0), Number(f[1] || 0), Number(f[2] || 0));
        });
    }
    function groups(cb) { run([ops, "groups"], (text) => cb(lines(text))); }
    function umask(cb) { run([ops, "umask"], (text) => cb(parseInt(text.trim(), 8))); }
    function setDefaultApp(mime, id, cb) { run([ops, "mimedefault", mime, id], (t, code) => cb(code === 0)); }
    // Left/Right in Quick Look: stops at the ends; an item no longer listed starts from the first
    function stepIndex(i, d, n) { return i < 0 ? 0 : Math.max(0, Math.min(n - 1, i + d)); }

    // ---- thumbnails (freedesktop cache, shared with Dolphin/GNOME) ----
    function thumbPath(path) {
        const uri = "file://" + path.split("/").map(s => encodeURIComponent(s)).join("/");
        return home + "/.cache/thumbnails/large/" + Qt.md5(uri) + ".png";
    }
    property var thumbExts: ({})           // extensions with a system thumbnailer (ops.sh thumbexts, read at startup)
    property var thumbFailed: ({})         // path -> true: failed this session, don't ask again (reassigned on change)
    function canThumb(item) {
        if (item.isDir || thumbFailed[item.path] || isRemote(item.path)) return false;   // never download for a picture
        const k = kindOf(item);
        return k === "image" || k === "video" || (k !== "code" && thumbExts[(item.suffix || "").toLowerCase()] === true);
    }
    property var thumbQueue: []            // [{ path, kind }]
    property int thumbBusy: 0
    signal thumbReady(string path)
    function requestThumb(path, kind) {
        if (!thumbQueue.some(q => q.path === path)) { thumbQueue.push({ path: path, kind: kind }); pumpThumbs(); }
    }
    function pumpThumbs() {
        while (thumbBusy < 3 && thumbQueue.length > 0) {
            const q = thumbQueue.shift();
            thumbBusy++;
            run([ops, "thumb", q.path, thumbPath(q.path), "256", q.kind], (t, code) => {
                thumbBusy--;
                if (code === 0) root.thumbReady(q.path);
                else root.thumbFailed = Object.assign({ [q.path]: true }, root.thumbFailed);
                pumpThumbs();
            });
        }
    }

    // ---- clipboard: ours, mirrored to the Wayland clipboard as text/uri-list for other apps ----
    property var clip: ({ mode: "", paths: [] })
    function uri(path) { return "file://" + path.split("/").map(s => encodeURIComponent(s)).join("/"); }
    function setClip(mode, paths) {
        clip = { mode: mode, paths: paths };
        const p = procComp.createObject(root, { command: ["wl-copy", "--type", "text/uri-list"], stdinEnabled: true });
        p.running = true;
        p.write(paths.map(uri).join("\r\n") + "\r\n");
        p.stdinEnabled = false;
        toast((mode === "move" ? "Cut " : "Copied ") + paths.length + (paths.length === 1 ? " item" : " items"), false);
    }
    function paste(dest) {
        // Our own clipboard first; otherwise files another app (Dolphin, Chrome...) put on the clipboard
        if (clip.paths.length > 0) return doPaste(clip.mode, dest, clip.paths);
        run(["wl-paste", "--no-newline", "--type", "text/uri-list"], (text, code) => {
            const paths = text.split(/\r?\n/).filter(l => l.startsWith("file://")).map(l => decodeURIComponent(l.slice(7)));
            if (code || paths.length === 0) return root.failed("Nothing to paste");
            doPaste("copy", dest, paths);
        });
    }
    function doPaste(mode, dest, paths) {
        toast((mode === "move" ? "Moving " : "Copying ") + paths.length + (paths.length === 1 ? " item…" : " items…"), false);
        run([ops, "paste", mode, dest].concat(paths), (text, code, err) => {
            const pairs = pastePairs(text, paths), made = pairs.map(p => p[1]);
            if (mode === "move" && made.length) {
                undoAction = { kind: "move", pairs: pairs.map(p => [p[1], p[0]]) };
                placesMoved(pairs);   // stars, pins and recent entries follow
                clip = { mode: "", paths: [] };
            } else if (made.length) {
                undoAction = { kind: "copy", paths: made };
            }
            if (err.trim()) failed(err.trim());
            if (made.length) toast((mode === "move" ? "Moved " : "Copied ") + made.length + (made.length === 1 ? " item" : " items"), true);
        });
    }

    // ---- operations with undo ----
    property var undoAction: null
    function trash(paths) {
        run([ops, "trash"].concat(paths), (text, code, err) => {
            if (code) return failed("Couldn't move to Trash: " + (err.trim() || "unknown error"));
            undoAction = { kind: "trash", uris: lines(text) };
            toast("Moved " + paths.length + (paths.length === 1 ? " item" : " items") + " to Trash", true);
        });
    }
    function deleteForever(paths) {
        run(["rm", "-rf", "--"].concat(paths), (t, code, err) => {
            if (code) return failed(err.trim());
            undoAction = null;
            toast("Deleted " + paths.length + (paths.length === 1 ? " item" : " items"), false);
        });
    }
    function rename(path, name, cb) {
        if (!name || name.indexOf("/") >= 0) return failed("A name can't be empty or contain /");
        const target = path.slice(0, path.lastIndexOf("/") + 1) + name;
        if (target === path) return;
        run(["mv", "-n", "-T", "--", path, target], (t, code, err) => {
            if (code) return failed(err.trim());
            run(["test", "-e", path], (t2, stillThere) => {
                if (stillThere === 0) return failed("“" + name + "” already exists");
                undoAction = { kind: "rename", from: target, to: path };
                placesMoved([[path, target]]);
                if (cb) cb(target);
            });
        });
    }
    function newFolder(dir) {
        run([ops, "mkdir", dir, "New Folder"], (text, code, err) => {
            if (code) return failed(err.trim());
            const made = lines(text)[0];
            undoAction = { kind: "copy", paths: [made] };
            created(made);
        });
    }
    function compress(dir, paths) {
        const names = paths.map(p => p.slice(p.lastIndexOf("/") + 1));
        const name = (paths.length === 1 ? names[0] : "Archive") + ".zip";
        toast("Compressing…", false);
        run([ops, "zip", dir, name].concat(names), (text, code, err) => {
            if (code) return failed(err.trim() || "Couldn't compress");
            undoAction = { kind: "copy", paths: lines(text) };
            toast("Created " + name, true);
        });
    }
    function extract(path) {
        toast("Extracting…", false);
        run([ops, "extract", path], (text, code, err) => {
            if (code) return failed(err.trim() || "Couldn't extract");
            undoAction = { kind: "copy", paths: lines(text) };
            toast("Extracted", true);
        });
    }
    function undo() {
        const a = undoAction;
        if (!a) return;
        undoAction = null;
        if (a.kind === "trash") run([ops, "restore"].concat(a.uris), (t, c, e) => c ? failed(e.trim()) : toast("Restored", false));
        else if (a.kind === "rename") run(["mv", "-n", "-T", "--", a.from, a.to], (t, c, e) => { if (c) return failed(e.trim()); placesMoved([[a.from, a.to]]); toast("Rename undone", false); });
        else if (a.kind === "move") {
            const back = [];
            let left = a.pairs.length;
            a.pairs.forEach(p => run(["mv", "-n", "-T", "--", p[0], p[1]], (t, c, e) => {
                if (c) failed(e.trim()); else back.push(p);
                if (--left === 0) placesMoved(back);   // one update for the whole undo
            }));
        }
        else if (a.kind === "copy" && a.paths.some(p => isRemote(p)))   // servers have no Trash: the copies we made go
            run(["rm", "-rf", "--"].concat(a.paths), (t, c, e) => c ? failed(e.trim()) : toast("Undone", false));
        else if (a.kind === "copy") run([ops, "trash"].concat(a.paths), (t, c, e) => c ? failed(e.trim()) : toast("Undone", false));
    }

    // ---- opening things ----
    function open(path) { Quickshell.execDetached(["gio", "open", path]); recentAdd(path); }
    function openIn(desktopFile, path) { Quickshell.execDetached(["gio", "launch", desktopFile, path]); recentAdd(path); }
    function openDolphin(path) { Quickshell.execDetached(["dolphin", path]); }
    function terminal(dir) { Quickshell.execDetached(["kitty", "--directory", dir]); }
    function setWallpaper(path) {
        run(["qs", "-c", "end4-pC", "ipc", "call", "wallpapers", "apply", path], (t, c, e) => c ? failed("Couldn't set the wallpaper") : toast("Wallpaper set", false));
    }
    function copyText(text) {
        const p = procComp.createObject(root, { command: ["wl-copy"], stdinEnabled: true });
        p.running = true; p.write(text); p.stdinEnabled = false;
        toast("Path copied", false);
    }
    // Apps registered for a file's type: [{ name, icon, file, isDefault }]
    function appsFor(path, cb) {
        run(["bash", "-c", "m=$(xdg-mime query filetype \"$1\"); echo \"MIME $m\"; gio mime \"$m\"", "_", path], (text) => {
            const mime = (/^MIME (.*)$/m.exec(text) || [])[1] ?? "";
            const ids = [];
            let def = "";
            for (const l of lines(text)) {
                let m = /^Default application for “?[^”]*”?: (.+\.desktop)$/.exec(l) || /^Default application for .*: (.+\.desktop)$/.exec(l);
                if (m) { def = m[1].trim(); continue; }
                m = /^\s+(\S+\.desktop)$/.exec(l);
                if (m && ids.indexOf(m[1]) < 0) ids.push(m[1]);
            }
            if (def && ids.indexOf(def) < 0) ids.unshift(def);
            const apps = [];
            for (const id of ids) {
                const bare = id.replace(/\.desktop$/, "");
                const e = DesktopEntries.byId(bare);
                if (e && e.noDisplay && id !== def) continue;
                // Entries may still be loading: fall back to a name made from the id
                const guess = bare.split(".").pop().replace(/[-_]/g, " ").replace(/^./, c => c.toUpperCase());
                apps.push({ name: e ? e.name : guess, icon: e ? e.icon : bare, id: id, isDefault: id === def });
            }
            apps.sort((a, b) => b.isDefault - a.isDefault);
            cb(apps, mime);
        });
    }
    function launchApp(id, path) { Quickshell.execDetached(["gtk-launch", id, path]); recentAdd(path); }
    // Details for the info panel: { modified, created, dims, count }
    function details(item, cb) {
        const cmd = item.isDir
            ? ["bash", "-c", "stat -c '%W' -- \"$1\"; find \"$1\" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l", "_", item.path]
            : (kindOf(item) === "image" && !isRemote(item.path)   // reading a server's picture downloads it
                ? ["bash", "-c", "stat -c '%W' -- \"$1\"; magick identify -format '%w × %h' \"$1[0]\" 2>/dev/null", "_", item.path]
                : ["stat", "-c", "%W", "--", item.path]);
        run(cmd, (text) => {
            const l = lines(text);
            const birth = Number(l[0]);
            cb({ created: birth > 0 ? date(new Date(birth * 1000)) : "", extra: l[1] ?? "" });
        });
    }

    // DesktopEntries scans on first use and answers null until then: start it now
    Component.onCompleted: {
        run([ops, "thumbexts"], (text) => { const m = {}; for (const e of lines(text)) m[e] = true; root.thumbExts = m; });
        run(["mkdir", "-p", "--", parentOf(bookmarksFile), parentOf(starredFile)], () => root.placesWatching = true);
        refreshPlaces(); refreshMounts(); void DesktopEntries.applications.values.length; }
}
