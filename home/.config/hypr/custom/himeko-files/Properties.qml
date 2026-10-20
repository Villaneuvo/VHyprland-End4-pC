import QtQuick
import QtQuick.Layouts

// Properties (Alt+Enter), laid out like GNOME Files 47: a hero (big icon, name, live size), boxed rows, and pages
// (Permissions, Enclosed, Open With, Details) that slide in, with popover dropdowns. Loaded on demand like Quick Look;
// the live folder count is stopped when it closes or the selection changes.
FocusScope {
    id: root
    required property var items
    required property var tab
    property Item backdrop
    property bool shown: true
    signal close()
    signal faded()
    signal go(string path)
    signal open()
    signal renamed(string path)

    readonly property bool one: items.length === 1
    readonly property var first: items[0]
    property var info: []                  // Fs.props, same order as items (null where unreadable)
    readonly property var firstInfo: info.length ? info[0] : null

    // ---- pages: the main page's navigation rows; in the Trash none (changing a trashed file breaks Restore) ----
    readonly property bool oneFile: one && !first.isDir
    readonly property var pages: tab.inTrash ? []
        : ["Permissions"].concat(oneFile ? ["Open With"] : [], metaRows.length ? ["Details"] : [])
    readonly property bool canRename: one && !first.isCurrent && !tab.inTrash
    readonly property string kindLabel: Fs.labelOf(Fs.kindOf(first), first.suffix)
    property string page: ""               // "" = main
    property int pageDir: 1
    readonly property string pageTitle: page === "Details" ? kindLabel + " Details"
        : page === "Enclosed" ? "Change Permissions for Enclosed Files" : page
    function goPage(name) {
        closePopover();
        if (name === page || (name !== "" && name !== "Enclosed" && pages.indexOf(name) < 0)) return;
        pageDir = name === "" || (page === "Enclosed" && name === "Permissions") ? -1 : 1;
        page = name;
        if (name === "Permissions" && !groups.length) Fs.groups((list) => root.groups = list);
        if (name === "Enclosed") Fs.umask((u) => root.enclosed = Fs.umaskLevels(u));
        slide.restart();
    }
    // Esc: the popover, else the rename field, else back a page, else close the card
    function back() {
        if (popoverKey) return closePopover();
        if (renaming) { renaming = false; return; }
        if (page === "Enclosed") return goPage("Permissions");
        if (page) return goPage("");
        close();
    }

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
    // ---- group: chgrp works without root for your own files and the groups you're in ----
    property var groups: []                // your groups (loaded when the Permissions page opens)
    readonly property bool canGroup: permsEditable
    readonly property string groupState: info.length ? Fs.shared(info.map(i => i ? i.group : "")) : ""
    function setGroup(name) {
        if (!canGroup || !name || name === groupState) return;
        const its = items;
        Fs.chgrp(name, its.map(it => it.path), () => Fs.props(its.map(it => it.path), (list) => { if (root.items === its) root.info = list; }));
    }
    // ---- enclosed files: levels for everything inside the folder, starting from the umask (as GNOME Files) ----
    property var enclosed: ({})            // { files: {u,g,o}, folders: {u,g,o} }
    property bool enclosedBusy: false
    function mergeEnclosed(change) {
        const e = { files: Object.assign({}, enclosed.files), folders: Object.assign({}, enclosed.folders) };
        for (const cls in change) Object.assign(e[cls], change[cls]);
        enclosed = e;
    }
    // Runs to the end even if the card closes (the user confirmed it with Change); the toast comes from Fs
    function applyEnclosed() {
        if (enclosedBusy || !enclosed.files || !one || !first.isDir || !permsEditable) return;
        enclosedBusy = true;
        Fs.chmodTree(first.path, Fs.symbolicAll(enclosed.files, false), Fs.symbolicAll(enclosed.folders, true), (changed, skipped, unreachable) => {
            const n = (x) => String(x).replace(/\B(?=(\d{3})+(?!\d))/g, ",");   // root may be gone: no helpers from it
            Fs.toast("Changed permissions of " + n(changed) + (changed === 1 ? " item" : " items") + (skipped ? ", " + n(skipped) + " skipped" : "")
                     + (unreachable ? ", " + n(unreachable) + " couldn't be reached" : ""), false);
            try { root.enclosedBusy = false; if (root.page === "Enclosed") root.goPage("Permissions"); } catch (e) {}
        });
    }
    readonly property var permsState: !info.length ? {}
        : Object.assign(mixedKinds ? { files: permsOf(false), folders: permsOf(true) } : permsOf(first.isDir),
                        { exec: execState, editable: permsEditable, group: groupState, canGroup: canGroup })
    // cls: "files", "folders" or "" (all items are one kind); who: u/g/o, or "exec" with level "on"/"off"
    // A click while a change is still running waits (latest wins) and is worked out from the refreshed modes,
    // so quick clicks can't undo each other
    property bool permsBusy: false
    property var pendingPerm: null
    function setPerm(cls, who, level) {
        if (!permsEditable || tab.inTrash) return;
        if (permsBusy) { pendingPerm = [cls, who, level]; return; }
        const isDir = cls === "folders" || (cls === "" && first.isDir), byMode = {};
        info.forEach((i, n) => {
            if (!i || items[n].isDir !== isDir) return;
            const m = who === "exec" ? Fs.withExec(i.mode, level === "on") : Fs.withAccess(i.mode, who, level, isDir);
            if (m !== i.mode) (byMode[m] = byMode[m] ?? []).push(items[n].path);
        });
        const its = items, modes = Object.keys(byMode);
        if (!modes.length) return;
        permsBusy = true;
        let left = modes.length;
        // Afterwards the rows show what stat says, also when chmod failed
        const refresh = () => {
            if (--left > 0) return;
            Fs.props(its.map(it => it.path), (list) => {
                root.permsBusy = false;
                if (root.items !== its) { root.pendingPerm = null; return; }
                root.info = list;
                const next = root.pendingPerm;
                root.pendingPerm = null;
                if (next) root.setPerm(next[0], next[1], next[2]);
            });
        };
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
        if (!canRename || !name || name === first.name) return;
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

    // ---- popover dropdowns: one popover for the card; rows ask for it by key ----
    property string popoverKey: ""
    property var popChoices: []
    property string popCurrent: ""
    property bool popSearch: false
    property var popPick: null
    property Item popAnchor: null
    property string popFilter: ""
    function closePopover() { popoverKey = ""; popPick = null; popAnchor = null; }
    function pick(choice) { const f = popPick; closePopover(); if (f) f(choice); }
    // What a key offers: { choices, current, searchable, pick } (later pages add their keys here)
    function choiceFor(key) {
        const k = key.split(":");
        if (k[0] === "access" && info.length) {
            const cls = k.length === 3 ? k[1] : "", who = k[k.length - 1];
            const isDir = cls === "folders" || (cls === "" && first.isDir);
            const st = cls ? permsState[cls] : permsState;
            return { choices: Fs.levelsFor(who, isDir), current: st ? st[who] : "", searchable: false,
                     pick: (l) => setPerm(cls, who, l) };
        }
        if (k[0] === "enclosed" && enclosed.files)
            return { choices: Fs.levelsFor(k[2], k[1] === "folders"), current: enclosed[k[1]][k[2]], searchable: false,
                     pick: (l) => mergeEnclosed({ [k[1]]: { [k[2]]: l } }) };
        if (key === "group" && canGroup)
            return { choices: groups, current: groupState, searchable: true, pick: (g) => setGroup(g) };
        return null;
    }
    function findRow(item, key) {
        if (!item) return null;
        if (item.key === key && item.anchorItem) return item;
        for (const c of item.children) { const r = findRow(c, key); if (r) return r; }
        return null;
    }
    function openKey(key, row) {
        const c = choiceFor(key), r = row ?? findRow(pageLoader.item, key);
        if (!c || !r || !r.active) return;
        popAnchor = r.anchorItem; popChoices = c.choices; popCurrent = c.current; popSearch = c.searchable;
        popPick = c.pick; popFilter = ""; popoverKey = key;
    }

    // ---- text for the hero ----
    function thousands(n) { return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ","); }
    readonly property string heroTitle: one ? first.name : title
    readonly property string heroSub: !info.length && !counting ? ""
        : needsCount ? thousands(countItems) + (countItems === 1 ? " item" : " items") + ", totalling " + Fs.size(countBytes)
        : firstInfo ? (firstInfo.description || "File") + " · " + Fs.size(firstInfo.size) : ""
    readonly property string heroFree: one && first.isDir && firstInfo && firstInfo.total > 0 ? Fs.size(firstInfo.avail) + " Free" : ""
    readonly property string permsSummary: !info.length ? "" : mixedKinds ? "Files and Folders" : (permsState.u ?? "")
    readonly property string defaultApp: { const d = apps.find(a => a.isDefault); return d ? d.name : "None"; }

    // ---- open/close motion (Quick Look's) ----
    property real reveal: shown ? 1 : 0
    Behavior on reveal { Anim { kind: "effects" } }
    onRevealChanged: if (!shown && reveal === 0) faded()
    property real pop: shown ? 1 : 0
    Behavior on pop { enabled: root.shown; Anim { kind: "fastSpatial" } }
    // Pages slide in from the side they come from
    property real slideT: 1
    NumberAnimation { id: slide; target: root; property: "slideT"; from: 0; to: 1; duration: Theme.dur("spatial"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve.spatial }

    // Everything is ours while open (Delete must not reach the folder view)
    Keys.onPressed: (e) => {
        const alt = e.modifiers & Qt.AltModifier;
        if (e.key === Qt.Key_Escape) back();
        else if ((alt && e.key === Qt.Key_Left) || e.key === Qt.Key_Backspace) { if (!renaming && page) goPage(page === "Enclosed" ? "Permissions" : ""); }
        e.accepted = true;
    }

    Rectangle { anchors.fill: parent; color: Theme.alpha(Theme.surfaceLowest, 0.45); opacity: root.reveal }
    // Overlays keep the wheel too: without onWheel a MouseArea lets it through and the folder behind scrolls
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: root.close(); onWheel: (e) => e.accepted = true }

    Glass {
        id: card
        backdrop: root.backdrop
        anchors.centerIn: parent
        width: Math.min(root.page === "Enclosed" ? 520 : 460, root.width * 0.86)   // Enclosed's long title needs room
        height: Math.min(bar.height + 12 + (pageLoader.item ? pageLoader.item.implicitHeight : 0) + 20, root.height * 0.86)
        radius: Theme.rPanel
        // Near-opaque, like the reference: the boxed rows must read cleanly over a busy folder
        tint: Theme.alpha(Theme.surfaceMid, 0.94)
        opacity: root.reveal
        scale: 0.94 + 0.06 * root.pop
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: root.closePopover(); onWheel: (e) => e.accepted = true }

        // Header bar: main page — Open and close; pages — back, centred title, close
        Item {
            id: bar
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
            height: 44
            IconButton {
                readonly property bool on: Fs.isStarred(root.first.path)
                visible: root.page === "" && root.one && !root.tab.inTrash && root.first.path.startsWith("/")
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                icon: "star"; filled: on; fg: on ? Theme.primary : Theme.text
                tip: on ? "Unstar" : "Star"
                onClicked: Fs.setStarred([root.first.path], !on)
            }
            IconButton {
                visible: root.page !== "" && root.page !== "Enclosed"
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                icon: "chevron_left"; tip: "Back (Esc)"
                onClicked: root.back()
            }
            // Enclosed: Cancel / title / Change, as in GNOME Files
            IconButton {
                visible: root.page === "Enclosed"
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                label: "Cancel"; bg: containsMouse ? Theme.hover : Theme.alpha(Theme.text, 0.08)
                onClicked: root.back()
            }
            IconButton {
                visible: root.page === "Enclosed"
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                label: root.enclosedBusy ? "Changing…" : "Change"; active: !root.enclosedBusy; enabledLook: !root.enclosedBusy
                onClicked: root.applyEnclosed()
            }
            Text {
                anchors.centerIn: parent
                width: parent.width - (root.page === "Enclosed" ? 200 : 120)
                horizontalAlignment: Text.AlignHCenter
                visible: root.page !== ""
                text: root.pageTitle
                elide: Text.ElideRight
                color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: 650
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 2
                IconButton { visible: root.page === "" && root.one; icon: "open_in_new"; tip: "Open"; onClicked: root.open() }
                IconButton { visible: root.page !== "Enclosed"; icon: "close"; tip: "Close"; onClicked: root.close() }
            }
        }

        Flickable {
            id: pageArea
            anchors { left: parent.left; right: parent.right; top: bar.bottom; bottom: parent.bottom; topMargin: 4; leftMargin: 16; rightMargin: 16; bottomMargin: 16 }
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: pageLoader.item ? pageLoader.item.implicitHeight : 0
            Loader {
                id: pageLoader
                width: pageArea.width
                x: (1 - root.slideT) * 40 * root.pageDir
                opacity: root.slideT
                sourceComponent: root.page === "" ? mainPage
                               : root.page === "Permissions" ? permissions
                               : root.page === "Open With" ? openWith
                               : root.page === "Details" ? details
                               : root.page === "Enclosed" ? enclosedPage : null
            }
        }
    }

    // ---- popover ----
    MouseArea {
        anchors.fill: parent
        visible: root.popoverKey !== ""
        acceptedButtons: Qt.AllButtons
        onPressed: root.closePopover()
        onWheel: (e) => e.accepted = true
    }
    Glass {
        id: popover
        visible: root.popoverKey !== ""
        backdrop: root.backdrop
        tint: Theme.alpha(Theme.surfaceHigh, 0.97)
        radius: 12
        width: Math.max(200, Math.min(300, popList.implicitWidth + 24))
        height: Math.min(popCol.implicitHeight + 12, root.height - 16)
        readonly property point at: root.popAnchor ? root.popAnchor.mapToItem(root, 0, 0) : Qt.point(0, 0)
        readonly property real below: at.y + (root.popAnchor ? root.popAnchor.height : 0) + 6
        // Under the value, flipped above when it would leave the window; never past the sides
        x: Math.max(8, Math.min(root.width - width - 8, at.x + (root.popAnchor ? root.popAnchor.width : 0) - width))
        y: below + height <= root.height - 8 ? below : Math.max(8, at.y - height - 6)
        scale: visible ? 1 : 0.94
        Behavior on scale { Anim { kind: "fastSpatial" } }
        onVisibleChanged: if (visible && root.popSearch) search.forceActiveFocus()
        MouseArea { anchors.fill: parent }
        ColumnLayout {
            id: popCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
            spacing: 2
            Rectangle {
                visible: root.popSearch
                Layout.fillWidth: true
                implicitHeight: 34; radius: 10
                color: Theme.alpha(Theme.text, 0.06)
                border.width: search.activeFocus ? 1 : 0
                border.color: Theme.primary
                RowLayout {
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                    spacing: 6
                    Icon { name: "search"; size: 16; color: Theme.textDim }
                    TextInput {
                        id: search
                        Layout.fillWidth: true
                        text: root.popFilter
                        onTextChanged: root.popFilter = text
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                        clip: true
                        Text { visible: !parent.text; text: "Search"; color: Theme.textDim; font: parent.font }
                    }
                }
            }
            Flickable {
                Layout.fillWidth: true
                implicitHeight: Math.min(popList.implicitHeight, 8 * 36)
                contentHeight: popList.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: popList
                    width: parent.width
                    Repeater {
                        model: root.popChoices.filter(c => !root.popFilter || c.toLowerCase().indexOf(root.popFilter.toLowerCase()) >= 0)
                        delegate: Rectangle {
                            required property string modelData
                            width: popList.width
                            implicitWidth: choiceText.implicitWidth + 56
                            height: 36; radius: 8
                            color: choiceArea.containsMouse ? Theme.hover : "transparent"
                            Text {
                                id: choiceText
                                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                text: parent.modelData
                                textFormat: Text.PlainText
                                color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                            }
                            Icon {
                                visible: parent.modelData === root.popCurrent
                                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                name: "check"; size: 18; color: Theme.primary
                            }
                            MouseArea { id: choiceArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.pick(parent.modelData) }
                        }
                    }
                }
            }
        }
    }

    // ---- pages ----
    Component {
        id: mainPage
        ColumnLayout {
            spacing: 12
            // Hero: big icon with the rename badge, name, live size, free space
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 4
                Item {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 96; implicitHeight: 96
                    Thumb { anchors.fill: parent; item: root.first; radius: 18; iconSize: 46 }
                    Rectangle {
                        visible: root.canRename && !root.renaming
                        width: 32; height: 32; radius: 16
                        anchors { right: parent.right; bottom: parent.bottom; rightMargin: -8; bottomMargin: -8 }
                        color: badge.containsMouse ? Theme.surfaceHighest : Theme.surfaceHigh
                        border.width: 2; border.color: Theme.chromeStrong
                        Icon { anchors.centerIn: parent; name: "edit"; size: 16 }
                        MouseArea { id: badge; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.renaming = true }
                    }
                }
                Text {
                    visible: !root.renaming
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    horizontalAlignment: Text.AlignHCenter
                    text: root.heroTitle
                    textFormat: Text.PlainText
                    elide: Text.ElideMiddle
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 18; font.weight: 650
                }
                Loader {
                    active: root.renaming
                    visible: active
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 8
                    Layout.preferredWidth: Math.min(320, parent.width)
                    sourceComponent: RenameField {
                        text: root.first.name
                        isDir: root.first.isDir
                        onAccepted: (name) => root.rename(name)
                        onCancelled: root.renaming = false
                    }
                }
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 6
                    visible: root.heroSub !== ""
                    Text { text: root.heroSub; textFormat: Text.PlainText; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13 }
                    Icon {
                        visible: root.counting
                        anchors.verticalCenter: parent.verticalCenter
                        name: "progress_activity"; size: 15; color: Theme.textDim
                        RotationAnimator on rotation { running: root.counting && Theme.animate; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                    }
                }
                Text {
                    visible: root.heroFree !== ""
                    Layout.alignment: Qt.AlignHCenter
                    text: root.heroFree
                    color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12
                }
            }
            PropGroup {
                PropRow {
                    show: root.parentPath !== ""
                    title: "Parent Folder"
                    value: root.parentPath.replace(Fs.home, "~") + (root.parentPath === "/" ? "" : "/")
                    icon: "folder_open"; iconTip: "Open the folder"
                    onIconClicked: root.go(root.parentPath)
                }
                PropRow {
                    show: root.one && root.firstInfo !== null && root.firstInfo.type === "link"
                    title: "Link Target"
                    value: root.firstInfo && root.firstInfo.target === "!broken" ? "Broken link" : root.firstInfo ? root.firstInfo.target : ""
                }
            }
            PropGroup {
                PropRow { show: root.oneFile && root.firstInfo !== null; title: "Size"; value: root.firstInfo ? Fs.sizeText(root.firstInfo.size) : "" }
                PropRow { show: root.one && root.firstInfo !== null; title: "Modified"; value: root.firstInfo ? Fs.fullDate(root.firstInfo.mtime) : "" }
                PropRow { show: root.one && root.firstInfo !== null && root.firstInfo.birth !== null; title: "Created"; value: root.firstInfo && root.firstInfo.birth ? Fs.fullDate(root.firstInfo.birth) : "" }
            }
            PropGroup {
                PropRow { kind: "nav"; show: root.pages.indexOf("Permissions") >= 0; title: "Permissions"; value: root.permsSummary; onClicked: root.goPage("Permissions") }
                PropRow { kind: "nav"; show: root.pages.indexOf("Open With") >= 0; title: "Open With"; value: root.defaultApp; onClicked: root.goPage("Open With") }
                PropRow { kind: "nav"; show: root.pages.indexOf("Details") >= 0; title: "Details"; value: root.kindLabel; onClicked: root.goPage("Details") }
            }
        }
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
        id: enclosedPage
        PropsEnclosed { props: root }
    }

    Component {
        id: permissions
        PropsPermissions { props: root }
    }
}
