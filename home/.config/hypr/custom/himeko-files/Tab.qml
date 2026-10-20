import QtQuick
import Qt.labs.folderlistmodel
import Quickshell.Io

// One tab: a folder, its history and how it is shown. `items` is the visible, sorted list (folders first).
QtObject {
    id: tab
    property string path: Fs.home
    property var back: []
    property var forward: []
    property string viewMode: "icons"      // icons | details
    property string sortKey: "name"        // name | modified | size | kind
    property bool sortDesc: false
    property string filter: "all"          // all | image | video | doc
    property string query: ""
    property bool showHidden: false
    property var selection: ({})           // path -> true
    property string current: ""            // keyboard focus
    property string anchor: ""             // shift-click range start
    property var counts: null              // subfolder path -> item count; null until counted
    property string countedPath: ""
    property int direction: 1              // 1 = into/forward, -1 = back/up: which way the content slides
    property real loadedAt: 0              // when the current folder was first listed (tiles animate in after it)
    property string loadedPath: ""
    function countOf(p) { return Fs.countOf(counts, p); }

    // Recent and Starred aren't folders: places.py lists them
    readonly property string place: path === Fs.recentPath ? "recent" : path === Fs.starredPath ? "starred" : path.startsWith("network:") ? "network" : ""
    readonly property bool virtual: place !== ""
    readonly property bool ready: virtual ? loadedPath === path : listPath !== "" && model.status === FolderListModel.Ready
    readonly property string name: place === "recent" ? "Recent" : place === "starred" ? "Starred"
        : place === "network" ? (path.length > 8 ? Fs.netHost(path.slice(8)) : "Network")
        : Fs.netMountOf(path, Fs.netMounts)?.path === path ? Fs.netMountOf(path, Fs.netMounts).name   // a server's top folder
        : path === "/" ? "/" : path === Fs.home ? "Home" : path.slice(path.lastIndexOf("/") + 1)
    readonly property bool inTrash: path === Fs.trashDir || path.startsWith(Fs.trashDir + "/")

    property FolderListModel model: FolderListModel {
        folder: tab.virtual || !tab.listPath ? "" : Fs.uri(tab.listPath)
        showDirsFirst: true
        showDotAndDotDot: false
        showHidden: tab.showHidden
        sortField: FolderListModel.Unsorted
        caseSensitive: false
    }

    // Qt's FolderListModel re-reads the folder path as a URL ("#"/"?" cut it short, "%20" turns into " "): such a
    // folder is listed through a symlink in XDG_RUNTIME_DIR, and its items get their real paths back
    property string listPath: ""
    function updateListPath() {
        if (virtual || !/[#?]|%[0-9A-Fa-f]{2}/.test(path)) return listPath = path;
        listPath = "";
        const asked = path, link = Fs.runtimeDir + "/dir-" + Qt.md5(path);
        Fs.run(["bash", "-c", "mkdir -p \"${2%/*}\" && ln -sfn -- \"$1\" \"$2\"", "_", path, link], () => { if (tab.path === asked) tab.listPath = link; });
    }

    property var all: []
    function reload() {
        if (virtual) return reloadPlace();
        if (!listPath) return;
        const m = tab.model, list = [], real = (p) => listPath === path ? p : path + p.slice(listPath.length);
        for (let i = 0; i < m.count; i++) {
            list.push({
                name: m.get(i, "fileName"), path: real(m.get(i, "filePath")), isDir: m.get(i, "fileIsDir"),
                size: m.get(i, "fileSize"), modified: m.get(i, "fileModified"), suffix: m.get(i, "fileSuffix")
            });
        }
        all = list;
        if (loadedPath !== path) { loadedPath = path; loadedAt = Date.now(); }
        // Count the subfolders once per visit (F5 resets countedPath); ignore answers for a folder we left
        if (countedPath !== path && list.some(it => it.isDir) && !Fs.isRemote(path)) {   // counting a server's folders downloads them
            const asked = path;
            countedPath = path;
            Fs.countSubfolders(asked, (c) => { if (tab.path === asked) tab.counts = c; });
        }
    }
    readonly property Connections watch: Connections {
        target: tab.model
        function onCountChanged() { reloadTimer.restart(); }
        function onStatusChanged() { if (tab.model.status === FolderListModel.Ready) reloadTimer.restart(); }
    }
    // Coalesce bursts of changes (a copy of 500 files) into one rebuild
    readonly property Timer reloadTimer: Timer { interval: 60; onTriggered: tab.reload() }

    function reloadPlace() {
        if (place === "network") { all = []; loadedPath = path; return; }   // NetworkPage lists it
        const asked = path;
        const done = (list) => {
            if (tab.path !== asked) return;   // answer for a place we left
            all = list;
            if (loadedPath !== path) { loadedPath = path; loadedAt = Date.now(); }
            const dirs = list.filter(it => it.isDir && !Fs.isRemote(it.path)).map(it => it.path);
            if (dirs.length) Fs.countFolders(dirs, (c) => { if (tab.path === asked) tab.counts = c; });
        };
        if (place === "recent") Fs.recentList(done);
        else Fs.starredList(done);
    }
    onPathChanged: { updateListPath(); if (virtual) reloadTimer.restart(); }
    // Changes from elsewhere: GTK's history (only while Recent is shown), stars, and our own operations (they toast)
    readonly property FileView recentWatch: FileView {
        path: tab.place === "recent" ? Fs.recentFile : ""
        preload: false; watchChanges: true; printErrors: false
        onFileChanged: tab.reloadTimer.restart()
    }
    readonly property Connections placeWatch: Connections {
        target: Fs
        enabled: tab.virtual
        function onStarredChanged() { if (tab.place === "starred") tab.reloadTimer.restart(); }
        function onToast() { tab.reloadTimer.restart(); }
    }

    readonly property var items: {
        const q = query.trim().toLowerCase();
        const f = filter;
        const matchKind = (it) => f === "all" || it.isDir || (f === "doc" ? ["doc", "pdf", "sheet", "slides"].indexOf(Fs.kindOf(it)) >= 0 : Fs.kindOf(it) === f);
        const list = all.filter(it => (!q || it.name.toLowerCase().indexOf(q) >= 0) && matchKind(it) && (f === "all" || !it.isDir || q));
        const dir = sortDesc ? -1 : 1;
        const byName = (a, b) => a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: "base" });
        const cmp = {
            name: byName,
            modified: (a, b) => (a.modified - b.modified) || byName(a, b),
            size: (a, b) => (a.size - b.size) || byName(a, b),
            kind: (a, b) => Fs.kindOf(a).localeCompare(Fs.kindOf(b)) || byName(a, b),
            location: (a, b) => Fs.parentOf(a.path).localeCompare(Fs.parentOf(b.path)) || byName(a, b),
            used: (a, b) => ((a.used ?? 0) - (b.used ?? 0)) || byName(a, b)
        }[sortKey] ?? byName;
        list.sort((a, b) => (b.isDir - a.isDir) || dir * cmp(a, b));
        return list;
    }
    readonly property var folders: items.filter(it => it.isDir)
    readonly property var files: items.filter(it => !it.isDir)
    readonly property var selectedItems: items.filter(it => selection[it.path])
    readonly property int selectedCount: selectedItems.length
    readonly property real selectedSize: selectedItems.reduce((s, it) => s + (it.isDir ? 0 : it.size), 0)
    readonly property var focusItem: items.find(it => it.path === current) ?? null

    property var folderSort: null          // [key, desc] to go back to when leaving Recent (newest first there)
    function go(p, record, dir) {
        if (!p || p === path) return;
        direction = dir ?? 1;
        if (record !== false) { back = back.concat([path]); forward = []; }
        if (p === Fs.recentPath) { folderSort = folderSort ?? [sortKey, sortDesc]; sortKey = "used"; sortDesc = true; }
        else if (folderSort) { sortKey = folderSort[0]; sortDesc = folderSort[1]; folderSort = null; }
        path = p.length > 1 && p.endsWith("/") ? p.slice(0, -1) : p;
        selection = ({}); current = ""; anchor = ""; query = "";
        all = [];
        counts = null; countedPath = "";
    }
    function goBack() { if (back.length) { forward = [path].concat(forward); const p = back[back.length - 1]; back = back.slice(0, -1); go(p, false, -1); } }
    function goForward() { if (forward.length) { back = back.concat([path]); const p = forward[0]; forward = forward.slice(1); go(p, false, 1); } }
    function goUp() {
        if (Fs.netMountOf(path, Fs.netMounts)?.path === path) return go("network:", true, -1);   // above a server: Network
        if (path !== "/" && !virtual) go(path.slice(0, path.lastIndexOf("/")) || "/", true, -1); }

    // Selection: plain click selects one, ctrl toggles, shift selects a range in the visible order
    function select(item, mods) {
        const s = Object.assign({}, selection);
        if (mods & Qt.ShiftModifier && anchor) {
            const a = items.findIndex(it => it.path === anchor), b = items.findIndex(it => it.path === item.path);
            if (!(mods & Qt.ControlModifier)) for (const k in s) delete s[k];
            for (let i = Math.min(a, b); i <= Math.max(a, b); i++) s[items[i].path] = true;
        } else if (mods & Qt.ControlModifier) {
            if (s[item.path]) delete s[item.path]; else s[item.path] = true;
            anchor = item.path;
        } else {
            for (const k in s) delete s[k];
            s[item.path] = true;
            anchor = item.path;
        }
        selection = s;
        current = item.path;
    }
    function selectAll() { const s = {}; items.forEach(it => s[it.path] = true); selection = s; }
    function clearSelection() { selection = ({}); }
    function selectPath(p) { const s = {}; s[p] = true; selection = s; current = p; anchor = p; }
    function paths() { return selectedItems.map(it => it.path); }

    Component.onCompleted: { updateListPath(); if (path === Fs.recentPath) { folderSort = [sortKey, sortDesc]; sortKey = "used"; sortDesc = true; } reloadTimer.restart(); }
}
