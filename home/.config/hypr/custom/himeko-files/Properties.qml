import QtQuick
import QtQuick.Layouts

// Properties (Alt+Enter): a glass card over the dimmed folder with General, Permissions, Open With and Details tabs.
// Loaded on demand like Quick Look; the live folder count is stopped when it closes or the selection changes.
FocusScope {
    id: root
    required property var items
    required property var tab
    property Item backdrop
    property bool shown: true
    signal close()
    signal faded()
    signal go(string path)
    signal renamed(string path)

    readonly property bool one: items.length === 1
    readonly property var first: items[0]
    property var info: []                  // Fs.props, same order as items (null where unreadable)
    readonly property var firstInfo: info.length ? info[0] : null

    // ---- tabs ----
    readonly property bool oneFile: one && !first.isDir
    readonly property var tabs: ["General", "Permissions"].concat(oneFile ? ["Open With"] : [], metaRows.length ? ["Details"] : [])
    readonly property string current: tabs.indexOf(Fs.propsTab) >= 0 ? Fs.propsTab : "General"
    function setTab(name) { if (tabs.indexOf(name) >= 0) Fs.propsTab = name; }

    // ---- loading; answers for a selection we've moved past are dropped ----
    property real countItems: 0
    property real countBytes: 0
    property bool counting: false
    property var counter: null
    readonly property bool needsCount: items.length > 1 || first.isDir
    function stopCount() { if (counter) counter.running = false; counter = null; counting = false; }
    function load() {
        info = []; apps = []; appMime = ""; metaRows = [];
        stopCount();
        countItems = 0; countBytes = 0;
        const its = items, paths = its.map(it => it.path);
        Fs.props(paths, (list) => { if (root.items === its) root.info = list; });
        if (its.length === 1 && !its[0].isDir) {
            loadApps();
            const kind = Fs.kindOf(its[0]);
            if (["image", "video", "audio", "pdf", "font"].indexOf(kind) >= 0)
                Fs.meta(its[0].path, kind, (rows) => { if (root.items === its) root.metaRows = rows; });
        }
        // From its, not needsCount: in onItemsChanged that binding can still hold the previous selection's value
        if (its.length === 1 && !its[0].isDir) return;
        counting = true;
        counter = Fs.dirSize(paths, (n, b, done) => {
            if (root.items !== its) return;
            root.countItems = n; root.countBytes = b;
            if (done) { root.counting = false; root.counter = null; }
        });
    }
    onItemsChanged: load()
    Component.onCompleted: load()
    Component.onDestruction: stopCount()

    // ---- permissions: rows per class (files / folders), changes go out as one chmod per resulting mode ----
    readonly property bool permsEditable: info.length === items.length && info.every(i => i && i.mine && i.type !== "link")
    readonly property bool mixedKinds: items.some(it => it.isDir) && items.some(it => !it.isDir)
    function infosOf(isDir) { return info.filter((i, n) => i && items[n].isDir === isDir); }
    function permsOf(isDir) {
        const is = infosOf(isDir), lvl = (who) => Fs.shared(is.map(i => Fs.accessOf(i.mode, who, isDir) || "Custom"));
        return { u: lvl("u"), g: lvl("g"), o: lvl("o") };
    }
    readonly property string execState: {
        const is = infosOf(false);
        return is.length ? Fs.shared(is.map(i => Fs.isExec(i.mode) ? "on" : "off")) : "";
    }
    readonly property var permsState: !info.length ? {}
        : mixedKinds ? { files: permsOf(false), folders: permsOf(true), exec: execState, editable: permsEditable }
        : Object.assign(permsOf(first.isDir), { exec: execState, editable: permsEditable })
    // cls: "files", "folders" or "" (all items are one kind); who: u/g/o, or "exec" with level "on"/"off"
    function setPerm(cls, who, level) {
        if (!permsEditable) return;
        const isDir = cls === "folders" || (cls === "" && first.isDir), byMode = {};
        info.forEach((i, n) => {
            if (!i || items[n].isDir !== isDir) return;
            const m = who === "exec" ? Fs.withExec(i.mode, level === "on") : Fs.withAccess(i.mode, who, level, isDir);
            if (m !== i.mode) (byMode[m] = byMode[m] ?? []).push(items[n].path);
        });
        const its = items, modes = Object.keys(byMode);
        let left = modes.length;
        // Afterwards the rows show what stat says, also when chmod failed
        const refresh = () => { if (--left === 0) Fs.props(its.map(it => it.path), (list) => { if (root.items === its) root.info = list; }); };
        modes.forEach(m => Fs.chmod(Number(m), byMode[m], refresh));
    }

    // ---- open with / details ----
    property var apps: []
    property string appMime: ""
    property var metaRows: []
    readonly property int appCount: apps.length
    readonly property int metaCount: metaRows.length
    function loadApps() {
        const its = items;
        Fs.appsFor(its[0].path, (a, m) => { if (root.items === its) { root.apps = a; root.appMime = m; } });
    }
    function setDefault(id) {
        const app = apps.find(a => a.id === id);
        if (!app || !appMime) return;
        const what = firstInfo && firstInfo.description ? firstInfo.description : appMime;
        Fs.setDefaultApp(appMime, id, (ok) => {
            if (!ok) return Fs.failed("Couldn't change the default app");
            Fs.toast(app.name + " is now the default for " + what, false);
            root.loadApps();
        });
    }

    property bool renaming: false
    function rename(name) {
        renaming = false;
        if (!one || first.isCurrent || !name || name === first.name) return;
        Fs.rename(first.path, name, (target) => root.renamed(target));
    }

    // ---- text for the rows (also read by the IPC state) ----
    function plural(n, word) { return n + " " + word + (n === 1 ? "" : "s"); }
    readonly property string countText: (counting ? "Counting… " : "")
        + plural(countItems, "item") + (counting ? ", " : ", totalling ") + Fs.size(countBytes)
    readonly property string sizeLine: !info.length ? "" : needsCount ? countText : (firstInfo ? Fs.sizeText(firstInfo.size) : "")
    readonly property string title: one ? first.name
        : plural(items.length, "item") + " (" + plural(items.filter(it => it.isDir).length, "folder") + ", "
          + plural(items.filter(it => !it.isDir).length, "file") + ")"
    readonly property string typeText: !one ? "" : first.isDir ? "Folder"
        : firstInfo ? (firstInfo.description || "File") + (firstInfo.mime ? " (" + firstInfo.mime + ")" : "") : ""
    function parentOf(p) { return p.slice(0, p.lastIndexOf("/")) || "/"; }
    readonly property string parentPath: {
        const ps = items.map(it => parentOf(it.path));
        return ps.every(p => p === ps[0]) ? ps[0] : "";
    }

    // ---- open/close motion (Quick Look's) ----
    property real reveal: shown ? 1 : 0
    Behavior on reveal { Anim { kind: "effects" } }
    onRevealChanged: if (!shown && reveal === 0) faded()
    property real pop: shown ? 1 : 0
    Behavior on pop { enabled: root.shown; Anim { kind: "fastSpatial" } }

    // Everything is ours while open (Delete must not reach the folder view)
    Keys.onPressed: (e) => {
        const ctrl = e.modifiers & Qt.ControlModifier;
        if (e.key === Qt.Key_Escape) close();
        else if (ctrl && (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab)) {
            const d = e.key === Qt.Key_Backtab || (e.modifiers & Qt.ShiftModifier) ? -1 : 1;
            setTab(tabs[(tabs.indexOf(current) + d + tabs.length) % tabs.length]);
        }
        e.accepted = true;
    }

    Rectangle { anchors.fill: parent; color: Theme.alpha(Theme.surfaceLowest, 0.45); opacity: root.reveal }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: root.close() }

    Glass {
        id: card
        backdrop: root.backdrop
        anchors.centerIn: parent
        width: Math.min(560, root.width * 0.86)
        height: Math.min(content.implicitHeight + 32, root.height * 0.86)
        radius: Theme.rPanel
        tint: Theme.chromeStrong
        opacity: root.reveal
        scale: 0.94 + 0.06 * root.pop
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 16
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Thumb { item: root.first; implicitWidth: 48; implicitHeight: 48; radius: 12; iconSize: 24 }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: root.title
                        textFormat: Text.PlainText
                        elide: Text.ElideMiddle
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: 600
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: root.typeText
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12
                    }
                }
                IconButton { icon: "close"; tip: "Close (Esc)"; onClicked: root.close() }
            }

            // Tab chips
            Row {
                visible: root.tabs.length > 1
                spacing: 6
                Repeater {
                    model: root.tabs
                    delegate: Rectangle {
                        required property string modelData
                        readonly property bool on: modelData === root.current
                        implicitWidth: chipText.implicitWidth + 28; implicitHeight: 34; radius: 17
                        color: on ? Theme.primary : chipArea.containsMouse ? Theme.hover : "transparent"
                        border.width: on ? 0 : 1
                        border.color: Theme.alpha(Theme.text, 0.12)
                        Text {
                            id: chipText
                            anchors.centerIn: parent
                            text: parent.modelData
                            color: parent.on ? Theme.inkPrimary : Theme.text
                            font.family: Theme.font; font.pixelSize: 13; font.weight: parent.on ? 600 : 450
                        }
                        MouseArea { id: chipArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setTab(parent.modelData) }
                    }
                }
            }

            Loader {
                id: page
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: root.current === "General" ? general
                               : root.current === "Permissions" ? permissions
                               : root.current === "Open With" ? openWith
                               : root.current === "Details" ? details : null
            }
        }
    }

    component Label: Text {
        Layout.alignment: Qt.AlignTop | Qt.AlignRight
        color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13
    }
    component Value: Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        wrapMode: Text.WrapAnywhere
        color: Theme.text; font.family: Theme.font; font.pixelSize: 13
    }

    Component {
        id: openWith
        PropsOpenWith { props: root }
    }

    Component {
        id: details
        PropsDetails { props: root }
    }

    Component {
        id: permissions
        PropsPermissions { props: root }
    }

    Component {
        id: general
        GridLayout {
            columns: 2
            columnSpacing: 14
            rowSpacing: 8
            readonly property var fi: root.firstInfo

            Label { text: "Name"; visible: root.one }
            RowLayout {
                visible: root.one
                Layout.fillWidth: true
                spacing: 4
                Value { visible: !root.renaming; text: root.first.name; Layout.fillWidth: true }
                IconButton {
                    visible: !root.renaming && !root.first.isCurrent
                    icon: "edit"; tip: "Rename"; iconSize: 16; implicitWidth: 30; implicitHeight: 30
                    onClicked: root.renaming = true
                }
                Loader {
                    active: root.renaming
                    Layout.fillWidth: true
                    sourceComponent: RenameField {
                        text: root.first.name
                        isDir: root.first.isDir
                        onAccepted: (name) => root.rename(name)
                        onCancelled: root.renaming = false
                    }
                }
            }
            Label { text: "Size" }
            Value { text: root.sizeLine }
            Label { text: "Link target"; visible: root.one && fi !== null && fi.type === "link" }
            Value { visible: root.one && fi !== null && fi.type === "link"; text: fi && fi.target === "!broken" ? "Broken link" : fi ? fi.target : "" }
            Label { text: "Location" }
            Text {
                Layout.fillWidth: true
                text: root.parentPath ? root.parentPath.replace(Fs.home, "~") : "Several folders"
                textFormat: Text.PlainText
                wrapMode: Text.WrapAnywhere
                color: root.parentPath ? Theme.primary : Theme.text
                font.family: Theme.font; font.pixelSize: 13; font.underline: locArea.containsMouse
                MouseArea {
                    id: locArea
                    anchors.fill: parent
                    enabled: root.parentPath !== ""
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.go(root.parentPath)
                }
            }
            Label { text: "Modified"; visible: root.one && fi !== null }
            Value { visible: root.one && fi !== null; text: fi ? Fs.fullDate(fi.mtime) : "" }
            Label { text: "Accessed"; visible: root.one && fi !== null }
            Value { visible: root.one && fi !== null; text: fi ? Fs.fullDate(fi.atime) : "" }
            Label { text: "Created"; visible: root.one && fi !== null && fi.birth !== null }
            Value { visible: root.one && fi !== null && fi.birth !== null; text: fi && fi.birth ? Fs.fullDate(fi.birth) : "" }
            Label { text: "Free space"; visible: root.one && fi !== null && fi.total > 0 }
            Value { visible: root.one && fi !== null && fi.total > 0; text: fi ? Fs.size(fi.avail) + " free of " + Fs.size(fi.total) : "" }
        }
    }
}
