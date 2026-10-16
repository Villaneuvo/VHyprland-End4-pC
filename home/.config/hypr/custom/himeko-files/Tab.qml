import QtQuick
import Qt.labs.folderlistmodel

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

    readonly property string name: path === "/" ? "/" : path === Fs.home ? "Home" : path.slice(path.lastIndexOf("/") + 1)
    readonly property bool inTrash: path === Fs.trashDir || path.startsWith(Fs.trashDir + "/")

    property FolderListModel model: FolderListModel {
        folder: "file://" + tab.path
        showDirsFirst: true
        showDotAndDotDot: false
        showHidden: tab.showHidden
        sortField: FolderListModel.Unsorted
        caseSensitive: false
    }

    property var all: []
    function reload() {
        const m = tab.model, list = [];
        for (let i = 0; i < m.count; i++) {
            list.push({
                name: m.get(i, "fileName"), path: m.get(i, "filePath"), isDir: m.get(i, "fileIsDir"),
                size: m.get(i, "fileSize"), modified: m.get(i, "fileModified"), suffix: m.get(i, "fileSuffix")
            });
        }
        all = list;
        if (loadedPath !== path) { loadedPath = path; loadedAt = Date.now(); }
        // Count the subfolders once per visit (F5 resets countedPath); ignore answers for a folder we left
        if (countedPath !== path && list.some(it => it.isDir)) {
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
            kind: (a, b) => Fs.kindOf(a).localeCompare(Fs.kindOf(b)) || byName(a, b)
        }[sortKey];
        list.sort((a, b) => (b.isDir - a.isDir) || dir * cmp(a, b));
        return list;
    }
    readonly property var folders: items.filter(it => it.isDir)
    readonly property var files: items.filter(it => !it.isDir)
    readonly property var selectedItems: items.filter(it => selection[it.path])
    readonly property int selectedCount: selectedItems.length
    readonly property real selectedSize: selectedItems.reduce((s, it) => s + (it.isDir ? 0 : it.size), 0)
    readonly property var focusItem: items.find(it => it.path === current) ?? null

    function go(p, record, dir) {
        if (!p || p === path) return;
        direction = dir ?? 1;
        if (record !== false) { back = back.concat([path]); forward = []; }
        path = p.length > 1 && p.endsWith("/") ? p.slice(0, -1) : p;
        selection = ({}); current = ""; anchor = ""; query = "";
        all = [];
        counts = null; countedPath = "";
    }
    function goBack() { if (back.length) { forward = [path].concat(forward); const p = back[back.length - 1]; back = back.slice(0, -1); go(p, false, -1); } }
    function goForward() { if (forward.length) { back = back.concat([path]); const p = forward[0]; forward = forward.slice(1); go(p, false, 1); } }
    function goUp() { if (path !== "/") go(path.slice(0, path.lastIndexOf("/")) || "/", true, -1); }

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

    Component.onCompleted: reloadTimer.restart()
}
