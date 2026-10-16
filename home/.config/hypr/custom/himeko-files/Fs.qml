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
            root.devices = list;
        });
        run(["bash", "-c", "ls -A \"$1\" 2>/dev/null | wc -l", "_", root.trashDir], (text) => root.trashCount = Number(text.trim()) || 0);
    }
    Timer { interval: 4000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refreshPlaces() }

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
    readonly property var kinds: ({
        image: { icon: "image", label: "Image", ext: ["jpg", "jpeg", "png", "gif", "webp", "avif", "bmp", "svg", "heic", "jxl", "tif", "tiff", "ico"] },
        video: { icon: "movie", label: "Video", ext: ["mp4", "mkv", "webm", "mov", "avi", "m4v"] },
        audio: { icon: "music_note", label: "Audio", ext: ["mp3", "flac", "ogg", "opus", "wav", "m4a", "aac"] },
        pdf: { icon: "picture_as_pdf", label: "PDF", ext: ["pdf"] },
        doc: { icon: "description", label: "Document", ext: ["txt", "md", "doc", "docx", "odt", "rtf", "epub"] },
        sheet: { icon: "table_chart", label: "Spreadsheet", ext: ["csv", "xls", "xlsx", "ods"] },
        slides: { icon: "slideshow", label: "Presentation", ext: ["ppt", "pptx", "odp"] },
        archive: { icon: "folder_zip", label: "Archive", ext: ["zip", "gz", "xz", "bz2", "zst", "tar", "7z", "rar", "tgz"] },
        code: { icon: "code", label: "Code", ext: ["js", "ts", "tsx", "jsx", "py", "sh", "lua", "qml", "json", "yml", "yaml", "toml", "html", "css", "c", "cpp", "h", "rs", "go", "java", "php", "sql", "conf", "ini", "xml"] },
        app: { icon: "deployed_code", label: "Application", ext: ["appimage", "deb", "exe", "desktop", "run"] },
        font: { icon: "font_download", label: "Font", ext: ["ttf", "otf", "woff", "woff2"] },
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

    // ---- thumbnails (freedesktop cache, shared with Dolphin/GNOME) ----
    function thumbPath(path) {
        const uri = "file://" + path.split("/").map(s => encodeURIComponent(s)).join("/");
        return home + "/.cache/thumbnails/large/" + Qt.md5(uri) + ".png";
    }
    property var thumbQueue: []
    property int thumbBusy: 0
    signal thumbReady(string path)
    function requestThumb(path) {
        if (thumbQueue.indexOf(path) < 0) { thumbQueue.push(path); pumpThumbs(); }
    }
    function pumpThumbs() {
        while (thumbBusy < 3 && thumbQueue.length > 0) {
            const src = thumbQueue.shift();
            thumbBusy++;
            run([ops, "thumb", src, thumbPath(src), "256"], (t, code) => {
                thumbBusy--;
                if (code === 0) root.thumbReady(src);
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
            const made = lines(text);
            if (mode === "move" && made.length) {
                undoAction = { kind: "move", pairs: made.map((t, i) => [t, paths[i]]) };
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
        else if (a.kind === "rename") run(["mv", "-n", "-T", "--", a.from, a.to], (t, c, e) => c ? failed(e.trim()) : toast("Rename undone", false));
        else if (a.kind === "move") a.pairs.forEach(p => run(["mv", "-n", "-T", "--", p[0], p[1]], (t, c, e) => { if (c) failed(e.trim()); }));
        else if (a.kind === "copy") run([ops, "trash"].concat(a.paths), (t, c, e) => c ? failed(e.trim()) : toast("Undone", false));
    }

    // ---- opening things ----
    function open(path) { Quickshell.execDetached(["gio", "open", path]); }
    function openIn(desktopFile, path) { Quickshell.execDetached(["gio", "launch", desktopFile, path]); }
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
        run(["bash", "-c", "gio mime \"$(xdg-mime query filetype \"$1\")\"", "_", path], (text) => {
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
            cb(apps);
        });
    }
    function launchApp(id, path) { Quickshell.execDetached(["gtk-launch", id, path]); }
    // Details for the info panel: { modified, created, dims, count }
    function details(item, cb) {
        const cmd = item.isDir
            ? ["bash", "-c", "stat -c '%W' -- \"$1\"; find \"$1\" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l", "_", item.path]
            : (kindOf(item) === "image"
                ? ["bash", "-c", "stat -c '%W' -- \"$1\"; magick identify -format '%w × %h' \"$1[0]\" 2>/dev/null", "_", item.path]
                : ["stat", "-c", "%W", "--", item.path]);
        run(cmd, (text) => {
            const l = lines(text);
            const birth = Number(l[0]);
            cb({ created: birth > 0 ? date(new Date(birth * 1000)) : "", extra: l[1] ?? "" });
        });
    }

    // DesktopEntries scans on first use and answers null until then: start it now
    Component.onCompleted: { refreshPlaces(); void DesktopEntries.applications.values.length; }
}
