import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// The whole window: glass sidebar, floating toolbar + tabs over the file view, status capsule, info panel,
// context menus, undo toasts and keyboard shortcuts.
FocusScope {
    id: root
    property string startPath: Fs.home
    property var tabs: []
    property int tabIndex: 0
    readonly property var tab: tabs[tabIndex] ?? null
    property bool infoOpen: false
    property bool railForced: false
    readonly property bool rail: railForced || width < 980
    property real zoom: 1.0
    property string renamingPath: ""
    property bool editingPath: false
    property bool searching: false

    Component { id: tabComp; Tab {} }
    function newTab(path, focusIt) {
        const t = tabComp.createObject(root, { path: path || Fs.home });
        tabs = tabs.concat([t]);
        if (focusIt !== false) tabIndex = tabs.length - 1;
    }
    function closeTab(i) {
        if (tabs.length === 1) return Qt.quit();
        const t = tabs[i];
        tabs = tabs.filter((x, j) => j !== i);
        if (tabIndex >= tabs.length) tabIndex = tabs.length - 1;
        else if (i < tabIndex) tabIndex--;
        t.destroy();
    }
    Component.onCompleted: { newTab(startPath); view.forceActiveFocus(); }

    readonly property string title: tab ? tab.name : "Files"

    // ---- actions ----
    function activate(item) {
        if (!item) return;
        if (item.isDir) tab.go(item.path);
        else Fs.open(item.path);
    }
    function openSelection() {
        const sel = tab.selectedItems;
        if (sel.length === 1) return activate(sel[0]);
        sel.filter(it => !it.isDir).forEach(it => Fs.open(it.path));
    }
    function startRename() {
        if (tab.selectedCount === 1 && !tab.inTrash) renamingPath = tab.selectedItems[0].path;
    }
    function finishRename(item, name) {
        renamingPath = "";
        view.forceActiveFocus();
        if (name && name !== item.name) Fs.rename(item.path, name, (target) => tab.selectPath(target));
    }
    function trashSelection() {
        if (!tab.selectedCount) return;
        if (tab.inTrash) return confirmDelete();
        Fs.trash(tab.paths());
    }
    function restoreSelection() {
        Fs.run([Fs.ops, "restore"].concat(tab.selectedItems.map(it => "trash:///" + encodeURIComponent(it.name))),
            (t, code, err) => code ? Fs.failed(err.trim()) : Fs.toast("Restored", false));
    }
    function confirmDelete() {
        const paths = tab.paths();
        if (!paths.length) return;
        showMenu(width / 2 - 150, height / 2 - 90, [], [
            { icon: "warning", label: "Delete " + paths.length + (paths.length === 1 ? " item" : " items") + " forever?", disabled: true },
            { separator: true },
            { icon: "delete_forever", label: "Delete permanently", danger: true, action: () => Fs.deleteForever(paths) },
            { icon: "close", label: "Cancel", action: () => {} }
        ]);
    }
    function goTo(text) {
        let p = text.trim().replace(/^~(?=\/|$)/, Fs.home);
        if (p.startsWith("file://")) p = decodeURIComponent(p.slice(7));
        if (!p.startsWith("/")) p = tab.path + "/" + p;
        Fs.run(["test", "-d", p], (t, code) => code ? Fs.failed("No such folder: " + text) : tab.go(p));
    }

    // Leaving a folder closes whatever was open on it
    Connections {
        target: root.tab
        function onPathChanged() { root.menuOpen = false; root.renamingPath = ""; root.editingPath = false; root.searching = false; navAnim.dir = root.tab.direction; navAnim.restart(); }
    }
    onTabIndexChanged: { navAnim.dir = 0; navAnim.restart(); }
    Connections {
        target: Fs
        function onToast(text, undoable) { toast.show(text, undoable && Fs.undoAction !== null, false); }
        function onFailed(text) { toast.show(text, false, true); }
        function onCreated(path) { root.tab.selectPath(path); root.renamingPath = path; }
    }

    // ---- menus ----
    property var menuQuick: []
    property var menuEntries: []
    property real menuX: 0
    property real menuY: 0
    property bool menuOpen: false
    function showMenu(x, y, quick, entries) {
        menuQuick = quick; menuEntries = entries; menuX = x; menuY = y; menuOpen = true;
        menuLoader.item?.forceActiveFocus();
    }
    function itemMenu(item, x, y) {
        const sel = tab.selectedItems, one = sel.length === 1 ? sel[0] : null;
        const kind = one ? Fs.kindOf(one) : "";
        if (tab.inTrash) {
            return showMenu(x, y, [], [
                { icon: "restore_from_trash", label: "Restore", bold: true, action: restoreSelection },
                { icon: "delete_forever", label: "Delete permanently", hint: "Shift+Del", danger: true, action: confirmDelete }
            ]);
        }
        const quick = [
            { icon: "content_cut", label: "Cut", action: () => Fs.setClip("move", tab.paths()) },
            { icon: "content_copy", label: "Copy", action: () => Fs.setClip("copy", tab.paths()) }
        ];
        if (one) quick.push({ icon: "edit", label: "Rename", action: startRename });
        quick.push({ icon: "delete", label: "Trash", danger: true, action: trashSelection });
        const e = [{ icon: "open_in_new", label: "Open", hint: "Enter", bold: true, action: openSelection }];
        if (one && !one.isDir) e.push({ icon: "apps", label: "Open with", sub: (done) => Fs.appsFor(one.path, apps => done(apps.length
            ? apps.map(a => ({ label: a.name + (a.isDefault ? "  ·  default" : ""), appIcon: Quickshell.iconPath(a.icon, true), action: () => Fs.launchApp(a.id, one.path) }))
            : [{ label: "No apps for this file", disabled: true }])) });
        if (one && one.isDir) e.push({ icon: "tab", label: "Open in new tab", action: () => newTab(one.path, false) });
        if (kind === "image") e.push({ icon: "wallpaper", label: "Set as wallpaper", action: () => Fs.setWallpaper(one.path) });
        if (one && Fs.isArchive(one)) e.push({ icon: "unarchive", label: "Extract here", action: () => Fs.extract(one.path) });
        else e.push({ icon: "folder_zip", label: "Compress to ZIP", action: () => Fs.compress(tab.path, tab.paths()) });
        e.push({ icon: "link", label: "Copy path", action: () => Fs.copyText(tab.paths().join("\n")) });
        if (one && one.isDir) e.push({ icon: "terminal", label: "Open terminal here", action: () => Fs.terminal(one.path) });
        e.push({ separator: true });
        e.push({ icon: "info", label: "Properties", hint: "F11", action: () => infoOpen = true });
        e.push({ icon: "folder_managed", label: "Show in Dolphin", action: () => Fs.openDolphin(one && one.isDir ? one.path : tab.path) });
        e.push({ icon: "delete_forever", label: "Delete permanently", hint: "Shift+Del", danger: true, action: confirmDelete });
        showMenu(x, y, quick, e);
    }
    function backgroundMenu(x, y) {
        if (tab.inTrash) {
            return showMenu(x, y, [], [
                { icon: "delete_sweep", label: "Empty Trash", danger: true, action: () => Fs.run(["gio", "trash", "--empty"], () => Fs.toast("Trash emptied", false)) }
            ]);
        }
        const sorts = [["name", "Name"], ["modified", "Modified"], ["size", "Size"], ["kind", "Kind"]];
        showMenu(x, y, [], [
            { icon: "create_new_folder", label: "New Folder", hint: "Ctrl+Shift+N", action: () => Fs.newFolder(tab.path) },
            { icon: "content_paste", label: "Paste", hint: "Ctrl+V", action: () => Fs.paste(tab.path) },
            { separator: true },
            { icon: "select_all", label: "Select all", hint: "Ctrl+A", action: () => tab.selectAll() },
            { icon: tab.showHidden ? "visibility_off" : "visibility", label: tab.showHidden ? "Hide hidden files" : "Show hidden files", hint: "Ctrl+H", action: () => tab.showHidden = !tab.showHidden },
            { icon: "sort", label: "Sort by", sub: sorts.map(s => ({ icon: tab.sortKey === s[0] ? "check" : "", label: s[1], action: () => setSort(s[0]) })) },
            { separator: true },
            { icon: "terminal", label: "Open terminal here", action: () => Fs.terminal(tab.path) },
            { icon: "folder_managed", label: "Open in Dolphin", action: () => Fs.openDolphin(tab.path) }
        ]);
    }
    function setSort(key) {
        if (tab.sortKey === key) tab.sortDesc = !tab.sortDesc;
        else { tab.sortKey = key; tab.sortDesc = key === "modified" || key === "size"; }
    }

    // ---- keyboard ----
    function moveFocus(dx, dy, mods) {
        const items = tab.items;
        if (!items.length) return;
        let i = items.findIndex(it => it.path === tab.current);
        if (i < 0) i = dx + dy > 0 ? -1 : items.length;
        const it0 = items[Math.max(0, Math.min(items.length - 1, i))];
        const cols = tab.viewMode === "details" ? 1 : (it0.isDir ? iconView.folderCols : iconView.fileCols);
        let j = i + dx + dy * cols;
        if (tab.viewMode !== "details" && dy !== 0 && it0.isDir !== (items[j]?.isDir ?? !it0.isDir)) {
            // Jumping between the folder rows and the file rows: land on the first/last item of the other section
            j = dy > 0 ? tab.folders.length : tab.folders.length - 1;
        }
        j = Math.max(0, Math.min(items.length - 1, j));
        tab.select(items[j], mods & Qt.ShiftModifier ? Qt.ShiftModifier : 0);
        ensureVisible(items[j].path);
    }
    function ensureVisible(path) {
        if (tab.viewMode === "details") {
            detailsView.positionViewAtIndex(tab.items.findIndex(it => it.path === path), ListView.Contain);
            return;
        }
        const fi = tab.folders.findIndex(it => it.path === path);
        let row;
        if (fi >= 0) row = 1 + Math.floor(fi / iconView.folderCols);
        else {
            const fr = tab.folders.length ? 1 + Math.ceil(tab.folders.length / iconView.folderCols) : 0;
            row = fr + 1 + Math.floor(tab.files.findIndex(it => it.path === path) / iconView.fileCols);
        }
        iconView.positionViewAtIndex(row, ListView.Contain);
    }

    Keys.onPressed: (e) => {
        const ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier, alt = e.modifiers & Qt.AltModifier;
        const k = e.key;
        let handled = true;
        if (ctrl && k === Qt.Key_L) { editingPath = true; searching = false; }
        else if (ctrl && k === Qt.Key_F) { searching = true; editingPath = false; }
        else if (ctrl && k === Qt.Key_T) newTab(tab.path);
        else if (ctrl && k === Qt.Key_W) closeTab(tabIndex);
        else if (ctrl && k === Qt.Key_Tab) tabIndex = (tabIndex + 1) % tabs.length;
        else if (ctrl && k === Qt.Key_Backtab) tabIndex = (tabIndex - 1 + tabs.length) % tabs.length;
        else if (ctrl && k === Qt.Key_H) tab.showHidden = !tab.showHidden;
        else if (ctrl && k === Qt.Key_A) tab.selectAll();
        else if (ctrl && k === Qt.Key_C && tab.selectedCount) Fs.setClip("copy", tab.paths());
        else if (ctrl && k === Qt.Key_X && tab.selectedCount && !tab.inTrash) Fs.setClip("move", tab.paths());
        else if (ctrl && k === Qt.Key_V && !tab.inTrash) Fs.paste(tab.path);
        else if (ctrl && k === Qt.Key_Z) Fs.undo();
        else if (ctrl && shift && k === Qt.Key_N) Fs.newFolder(tab.path);
        else if (ctrl && k === Qt.Key_1) tab.viewMode = "icons";
        else if (ctrl && k === Qt.Key_2) tab.viewMode = "details";
        else if (ctrl && (k === Qt.Key_Plus || k === Qt.Key_Equal)) zoom = Math.min(2, zoom + 0.15);
        else if (ctrl && k === Qt.Key_Minus) zoom = Math.max(0.6, zoom - 0.15);
        else if (ctrl && k === Qt.Key_0) zoom = 1;
        else if (alt && k === Qt.Key_Left) tab.goBack();
        else if (alt && k === Qt.Key_Right) tab.goForward();
        else if ((alt && k === Qt.Key_Up) || k === Qt.Key_Backspace) tab.goUp();
        else if (alt && (k === Qt.Key_Return || k === Qt.Key_Enter)) infoOpen = !infoOpen;
        else if (k === Qt.Key_F2) startRename();
        else if (k === Qt.Key_F5) { tab.countedPath = ""; tab.counts = null; tab.reload(); }
        else if (k === Qt.Key_F9) railForced = !railForced;
        else if (k === Qt.Key_F11) infoOpen = !infoOpen;
        else if (shift && k === Qt.Key_Delete) confirmDelete();
        else if (k === Qt.Key_Delete) trashSelection();
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) openSelection();
        else if (k === Qt.Key_Left) moveFocus(-1, 0, e.modifiers);
        else if (k === Qt.Key_Right) moveFocus(1, 0, e.modifiers);
        else if (k === Qt.Key_Up) moveFocus(0, -1, e.modifiers);
        else if (k === Qt.Key_Down) moveFocus(0, 1, e.modifiers);
        else if (k === Qt.Key_Home && tab.items.length) { tab.select(tab.items[0], 0); ensureVisible(tab.items[0].path); }
        else if (k === Qt.Key_End && tab.items.length) { const l = tab.items[tab.items.length - 1]; tab.select(l, 0); ensureVisible(l.path); }
        else if (k === Qt.Key_Escape) { if (tab.query) tab.query = ""; else tab.clearSelection(); searching = false; }
        else if (!ctrl && !alt && e.text.length === 1 && e.text > " ") { searching = true; tab.query += e.text; }
        else handled = false;
        e.accepted = handled;
    }

    // ---- window glass: thin tint everywhere, sheen, accent edge ----
    Rectangle {
        anchors.fill: parent
        radius: Theme.rWindow
        color: Theme.alpha(Theme.surface, 0.30)
        Sheen { radius: parent.radius; light: 0.05; tint: 0.10; edge: 0 }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 1.5
            border.color: Theme.alpha(Theme.primary, 0.45)
        }
    }

    // ---- layout ----
    RowLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        Sidebar {
            Layout.fillHeight: true
            tab: root.tab
            rail: root.rail
            onOpen: (p) => { root.tab.go(p); view.forceActiveFocus(); }
            onOpenDolphin: (p) => Fs.openDolphin(p)
        }

        Rectangle {
            id: main
            readonly property bool tight: width < 640
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.rPanel
            color: Theme.content
            clip: true

            // The scrolling content: the glass capsules above blur this
            Item {
                id: view
                anchors.fill: parent
                focus: true
                Keys.forwardTo: [root]
                transform: Translate { id: viewShift }

                IconGrid {
                    id: iconView
                    anchors.fill: parent
                    opacity: root.tab && root.tab.viewMode === "icons" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { Anim { kind: "effects" } }
                    tab: root.tab
                    zoom: root.zoom
                    topMargin: 134; pad: 24
                    headerComponent: headerComp
                    renamingPath: root.renamingPath
                    onActivated: (it) => root.activate(it)
                    onItemMenu: (it, x, y) => { const p = mapToItem(root, x, y); root.itemMenu(it, p.x, p.y); }
                    onBackgroundMenu: (x, y) => { const p = mapToItem(root, x, y); root.backgroundMenu(p.x, p.y); }
                    onRenamed: (it, name) => root.finishRename(it, name)
                    onRenameCancelled: { root.renamingPath = ""; view.forceActiveFocus(); }
                }
                DetailsList {
                    id: detailsView
                    anchors.fill: parent
                    opacity: root.tab && root.tab.viewMode === "details" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { Anim { kind: "effects" } }
                    tab: root.tab
                    topMargin: 134; pad: 24
                    headerComponent: headerComp
                    renamingPath: root.renamingPath
                    onActivated: (it) => root.activate(it)
                    onItemMenu: (it, x, y) => { const p = mapToItem(root, x, y); root.itemMenu(it, p.x, p.y); }
                    onBackgroundMenu: (x, y) => { const p = mapToItem(root, x, y); root.backgroundMenu(p.x, p.y); }
                    onRenamed: (it, name) => root.finishRename(it, name)
                    onRenameCancelled: { root.renamingPath = ""; view.forceActiveFocus(); }
                }

                // Empty states
                ColumnLayout {
                    visible: root.tab && root.tab.model.status === 2 && root.tab.items.length === 0 && root.tab.all.length >= 0
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 60
                    spacing: 10
                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 96; implicitHeight: 96
                        Shape { anchors.fill: parent; kind: "flower"; color: Theme.surfaceHigh }
                        Icon { anchors.centerIn: parent; name: root.tab && root.tab.query ? "search_off" : (root.tab && root.tab.inTrash ? "delete" : "folder_open"); size: 40; color: Theme.textDim }
                        Icon { x: 78; y: -6; name: "star"; filled: true; size: 18; color: Theme.tertiary }
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.tab && root.tab.query ? "Nothing matches “" + root.tab.query + "”" : (root.tab && root.tab.inTrash ? "Trash is empty" : "This folder is empty")
                        color: Theme.textDim; font.family: Theme.font; font.pixelSize: 15
                    }
                }
            }

            // Opening a folder: the content fades in while sliding 12 px from the side it came from
            ParallelAnimation {
                id: navAnim
                property int dir: 1
                Anim { target: viewShift; property: "x"; from: 12 * navAnim.dir; to: 0; kind: "effects"; duration: Theme.animate ? 250 : 0 }
                Anim { target: view; property: "opacity"; from: 0; to: 1; kind: "effects"; duration: Theme.animate ? 250 : 0 }
            }

            // Scroll edge effect (iOS): once content scrolls under the toolbar and tabs, it fades out first.
            // Opacity follows the scroll offset: 0 at rest, so the large title is never dimmed.
            Rectangle {
                readonly property var list: root.tab && root.tab.viewMode === "details" ? detailsView : iconView
                readonly property real chromeBottom: tabStrip.y + tabStrip.height
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: chromeBottom + 60
                // At rest contentY = originY - topMargin (the list header makes originY negative)
                opacity: Math.max(0, Math.min(1, (list.contentY - list.originY + list.topMargin) / 40))
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.alpha(Theme.surface, 0.95) }
                    GradientStop { position: 0.68; color: Theme.alpha(Theme.surface, 0.85) }
                    GradientStop { position: 1.0; color: Theme.alpha(Theme.surface, 0) }
                }
            }

            // ---- floating toolbar (glass over the content) ----
            RowLayout {
                id: toolbar
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 10
                height: 52

                Glass {
                    backdrop: view
                    implicitWidth: navRow.implicitWidth + 8; implicitHeight: 52
                    Row {
                        id: navRow
                        anchors.centerIn: parent
                        IconButton { icon: "arrow_back"; tip: "Back"; enabledLook: root.tab && root.tab.back.length > 0; onClicked: root.tab.goBack() }
                        IconButton { icon: "arrow_forward"; tip: "Forward"; enabledLook: root.tab && root.tab.forward.length > 0; onClicked: root.tab.goForward() }
                    }
                }

                Glass {
                    id: pathCapsule
                    backdrop: view
                    Layout.fillWidth: true
                    implicitHeight: 52
                    tint: root.editingPath || root.searching ? Theme.surfaceHigh : Theme.chrome
                    Rectangle {
                        anchors.fill: parent; radius: height / 2; color: "transparent"
                        border.width: 2; border.color: Theme.primary
                        opacity: root.editingPath || root.searching ? 1 : 0
                        Behavior on opacity { Anim { kind: "effects" } }
                    }
                    // Breadcrumbs
                    Flickable {
                        id: crumbs
                        opacity: root.editingPath || root.searching ? 0 : 1
                        visible: opacity > 0
                        Behavior on opacity { Anim { kind: "effects" } }
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        contentWidth: crumbRow.implicitWidth
                        clip: true
                        flickableDirection: Flickable.HorizontalFlick
                        readonly property var parts: {
                            if (!root.tab) return [];
                            const p = root.tab.path, out = [];
                            if (p.startsWith(Fs.home)) {
                                out.push({ label: "Home", path: Fs.home, icon: "home" });
                                let acc = Fs.home;
                                for (const s of p.slice(Fs.home.length).split("/").filter(x => x)) { acc += "/" + s; out.push({ label: s, path: acc }); }
                            } else {
                                out.push({ label: "", path: "/", icon: "hard_drive" });
                                let acc = "";
                                for (const s of p.split("/").filter(x => x)) { acc += "/" + s; out.push({ label: s, path: acc }); }
                            }
                            return out;
                        }
                        // Measured with an invisible row of plain texts; collapse when the real row wouldn't fit
                        readonly property bool collapse: parts.length > 3 && measure.implicitWidth > width
                        Row {
                            id: measure
                            visible: false
                            spacing: 22
                            Repeater { model: crumbs.parts; delegate: Text { required property var modelData; text: modelData.label || "XX"; font.family: Theme.font; font.pixelSize: 14; font.weight: 600 } }
                        }
                        function toEnd() { contentX = Math.max(0, contentWidth - width); }
                        onContentWidthChanged: toEnd()
                        onWidthChanged: toEnd()
                        MouseArea {
                            width: Math.max(crumbs.width, crumbRow.implicitWidth); height: crumbs.height
                            onClicked: root.editingPath = true
                        }
                        Row {
                            id: crumbRow
                            height: parent.height
                            spacing: 2
                            Repeater {
                                // Collapsed: first, "…", last two; in a very narrow window just "…" and the current folder
                                model: !crumbs.collapse ? crumbs.parts
                                    : main.tight ? [{ label: "…", path: "", ellipsis: true, hidden: crumbs.parts.slice(0, -1) }, crumbs.parts[crumbs.parts.length - 1]]
                                    : [crumbs.parts[0], { label: "…", path: "", ellipsis: true, hidden: crumbs.parts.slice(1, -2) }].concat(crumbs.parts.slice(-2))
                                delegate: Row {
                                    required property var modelData
                                    required property int index
                                    height: crumbRow.height
                                    spacing: 2
                                    Icon { visible: index > 0; name: "chevron_right"; size: 16; color: Theme.outline; anchors.verticalCenter: parent.verticalCenter }
                                    MouseArea {
                                        readonly property bool last: modelData.path === root.tab.path
                                        anchors.verticalCenter: parent.verticalCenter
                                        implicitWidth: crumbContent.implicitWidth + 20; implicitHeight: 36
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (modelData.ellipsis) {
                                                const p = mapToItem(root, 0, height + 6);
                                                root.showMenu(p.x, p.y, [], modelData.hidden.slice().reverse().map(c => ({ icon: c.icon ?? "folder", label: c.label || "/", action: () => root.tab.go(c.path) })));
                                            } else if (last) root.editingPath = true;
                                            else root.tab.go(modelData.path);
                                        }
                                        Rectangle { anchors.fill: parent; radius: 18; color: parent.last ? Theme.alpha(Theme.text, 0.10) : (parent.containsMouse ? Theme.hover : "transparent") }
                                        Row {
                                            id: crumbContent
                                            anchors.centerIn: parent
                                            spacing: 6
                                            Icon { visible: !!modelData.icon; name: modelData.icon ?? ""; size: 18; color: Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
                                            Text {
                                                visible: modelData.label !== ""
                                                // the current folder's name ellipsizes in a very narrow window instead of being cut
                                                width: Math.min(implicitWidth, Math.max(40, crumbs.width - 70))
                                                elide: Text.ElideMiddle
                                                text: modelData.label
                                                color: parent.parent.last ? Theme.text : Theme.textDim
                                                font.family: Theme.font; font.pixelSize: 14; font.weight: parent.parent.last ? 600 : 450
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    // Path editor / search field
                    RowLayout {
                        opacity: root.editingPath || root.searching ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { Anim { kind: "effects" } }
                        anchors { fill: parent; leftMargin: 18; rightMargin: 8 }
                        spacing: 10
                        Icon { name: root.searching ? "search" : "folder"; size: 19; color: Theme.textDim }
                        TextInput {
                            id: field
                            Layout.fillWidth: true
                            color: Theme.text
                            selectionColor: Theme.primaryContainer
                            selectedTextColor: Theme.inkPrimaryContainer
                            font.family: Theme.font; font.pixelSize: 14
                            clip: true
                            Text {
                                visible: field.text === "" && root.searching
                                text: "Search in " + (root.tab ? root.tab.name : "")
                                color: Theme.outline; font: field.font
                            }
                            onTextEdited: if (root.searching) root.tab.query = text
                            Keys.onEscapePressed: { if (root.searching) root.tab.query = ""; root.searching = false; root.editingPath = false; view.forceActiveFocus(); }
                            Keys.onReturnPressed: {
                                if (root.editingPath) { root.goTo(text); root.editingPath = false; }
                                else root.searching = false;
                                view.forceActiveFocus();
                            }
                            Keys.onDownPressed: { root.searching = false; view.forceActiveFocus(); root.moveFocus(0, 1, 0); }
                            onActiveFocusChanged: if (!activeFocus && root.editingPath) root.editingPath = false
                        }
                        IconButton {
                            implicitWidth: 36; implicitHeight: 36; iconSize: 18
                            icon: "close"; tip: "Close"
                            onClicked: { if (root.searching) root.tab.query = ""; root.searching = false; root.editingPath = false; view.forceActiveFocus(); }
                        }
                    }
                }

                Glass {
                    visible: !main.tight
                    backdrop: view
                    implicitWidth: modeRow.implicitWidth + 8; implicitHeight: 52
                    Row {
                        id: modeRow
                        anchors.centerIn: parent
                        spacing: 2
                        IconButton { icon: "grid_view"; tip: "Icons (Ctrl+1)"; active: root.tab && root.tab.viewMode === "icons"; onClicked: root.tab.viewMode = "icons" }
                        IconButton { icon: "view_list"; tip: "Details (Ctrl+2)"; active: root.tab && root.tab.viewMode === "details"; onClicked: root.tab.viewMode = "details" }
                    }
                }
                Glass {
                    visible: main.tight
                    backdrop: view
                    implicitWidth: 52; implicitHeight: 52
                    IconButton {
                        anchors.centerIn: parent
                        icon: root.tab && root.tab.viewMode === "icons" ? "grid_view" : "view_list"
                        tip: root.tab && root.tab.viewMode === "icons" ? "Switch to details (Ctrl+2)" : "Switch to icons (Ctrl+1)"
                        onClicked: root.tab.viewMode = root.tab.viewMode === "icons" ? "details" : "icons"
                    }
                }
                Glass {
                    backdrop: view
                    implicitWidth: 52; implicitHeight: 52
                    IconButton { anchors.centerIn: parent; icon: "search"; tip: "Search (Ctrl+F)"; active: root.searching; onClicked: { root.searching = !root.searching; root.editingPath = false; if (!root.searching) { root.tab.query = ""; view.forceActiveFocus(); } } }
                }
                Glass {
                    backdrop: view
                    implicitWidth: 52; implicitHeight: 52
                    IconButton {
                        id: moreBtn
                        anchors.centerIn: parent; icon: "more_horiz"; tip: "More"
                        onClicked: { const p = moreBtn.mapToItem(root, -240, 50); root.backgroundMenu(p.x, p.y); }
                    }
                }
            }
            onVisibleChanged: {}
            Connections {
                target: root
                function onEditingPathChanged() { if (root.editingPath) { field.text = root.tab.path.replace(Fs.home, "~"); field.forceActiveFocus(); field.selectAll(); } }
                function onSearchingChanged() { if (root.searching) { field.text = root.tab.query; field.forceActiveFocus(); field.cursorPosition = field.text.length; } }
            }

            // ---- tabs ----
            // The active tab's glass pill: one pill that glides between tabs
            Glass {
                readonly property Item at: { void root.tabs.length; return tabRepeater.itemAt(root.tabIndex); }
                visible: at !== null
                backdrop: view
                tint: Theme.chromeStrong
                x: tabStrip.x + (at ? at.x : 0)
                y: tabStrip.y
                width: at ? at.width : 0
                height: 44
                Behavior on x { Anim { kind: "fastSpatial" } }
            }
            Row {
                id: tabStrip
                anchors { left: parent.left; top: toolbar.bottom; leftMargin: 12; topMargin: 10 }
                spacing: 6
                Repeater {
                    id: tabRepeater
                    model: root.tabs
                    delegate: MouseArea {
                        id: tabItem
                        required property var modelData
                        required property int index
                        readonly property bool on: index === root.tabIndex
                        readonly property bool closable: on && root.tabs.length > 1
                        implicitWidth: 16 + tabRow.implicitWidth + (closable ? 8 : 16); implicitHeight: 44
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (e) => e.button === Qt.MiddleButton ? root.closeTab(index) : root.tabIndex = index
                        transformOrigin: Item.Left
                        Component.onCompleted: if (Theme.animate && root.tabs.length > 1) { scale = 0.8; grow.start(); }
                        Anim { id: grow; target: tabItem; property: "scale"; to: 1; kind: "fastSpatial" }
                        Rectangle { anchors.fill: parent; radius: 22; visible: !parent.on && parent.containsMouse; color: Theme.hover }
                        Row {
                            id: tabRow
                            anchors.verticalCenter: parent.verticalCenter
                            x: 16
                            spacing: 8
                            Rectangle { visible: on; width: 8; height: 8; radius: 4; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                text: modelData.name
                                color: on ? Theme.text : Theme.textDim
                                font.family: Theme.font; font.pixelSize: 13; font.weight: on ? 600 : 450
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            IconButton {
                                visible: closable
                                implicitWidth: 28; implicitHeight: 28; iconSize: 15
                                icon: "close"; tip: "Close tab"
                                anchors.verticalCenter: parent.verticalCenter
                                onClicked: root.closeTab(index)
                            }
                        }
                        Accessible.role: Accessible.PageTab
                        Accessible.name: modelData.name
                    }
                }
                IconButton { icon: "add"; tip: "New tab (Ctrl+T)"; fg: Theme.textDim; onClicked: root.newTab(root.tab.path) }
            }

            // ---- status capsule ----
            Glass {
                id: status
                backdrop: view
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 16 }
                implicitWidth: statusRow.implicitWidth + 28; implicitHeight: 52
                tint: Theme.chromeStrong
                RowLayout {
                    id: statusRow
                    anchors.centerIn: parent
                    spacing: 14
                    Text {
                        text: !root.tab ? "" : root.tab.selectedCount
                            ? root.tab.selectedCount + " selected" + (root.tab.selectedSize ? " · " + Fs.size(root.tab.selectedSize) : "")
                            : (root.tab.folders.length + " folders · " + root.tab.files.length + " files")
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: root.tab && root.tab.selectedCount ? 650 : 450
                    }
                    Rectangle { visible: root.tab && root.tab.viewMode === "icons"; implicitWidth: 1; implicitHeight: 22; color: Theme.edge }
                    RowLayout {
                        visible: root.tab && root.tab.viewMode === "icons"
                        spacing: 8
                        Icon { name: "photo_size_select_small"; size: 17; color: Theme.textDim }
                        Item {
                            implicitWidth: 120; implicitHeight: 28
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 6; radius: 3; color: Theme.alpha(Theme.text, 0.14) }
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * (root.zoom - 0.6) / 1.4; height: 6; radius: 3; color: Theme.primary }
                            Rectangle {
                                x: parent.width * (root.zoom - 0.6) / 1.4 - 9; anchors.verticalCenter: parent.verticalCenter
                                width: 18; height: 18; radius: 9; color: Theme.primary
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                function set(x) { root.zoom = Math.max(0.6, Math.min(2, 0.6 + 1.4 * x / width)); }
                                onPressed: (e) => set(e.x)
                                onPositionChanged: (e) => { if (pressed) set(e.x); }
                            }
                            Accessible.role: Accessible.Slider
                            Accessible.name: "Icon size"
                        }
                    }
                    Rectangle { implicitWidth: 1; implicitHeight: 22; color: Theme.edge }
                    IconButton {
                        implicitWidth: 40; implicitHeight: 40
                        icon: "info"; tip: "Information panel (F11)"; active: root.infoOpen
                        onClicked: root.infoOpen = !root.infoOpen
                    }
                }
            }

            // ---- toast ----
            Glass {
                id: toast
                property string text: ""
                property bool undoable: false
                property bool error: false
                backdrop: view
                anchors { horizontalCenter: parent.horizontalCenter; bottom: status.top; bottomMargin: 10 }
                implicitWidth: toastRow.implicitWidth + 24; implicitHeight: 52
                tint: error ? Theme.alpha(Theme.surfaceHighest, 0.95) : Theme.menu
                opacity: 0
                visible: opacity > 0
                Behavior on opacity { Anim { kind: "effects" } }
                transform: Translate { id: toastLift }
                Anim { id: toastRise; target: toastLift; property: "y"; from: 16; to: 0; kind: "enter" }
                function show(t, u, err) { text = t; undoable = u; error = err; opacity = 1; hideTimer.restart(); toastRise.restart(); }
                Timer { id: hideTimer; interval: 4500; onTriggered: toast.opacity = 0 }
                RowLayout {
                    id: toastRow
                    anchors.centerIn: parent
                    spacing: 12
                    Item {
                        implicitWidth: 34; implicitHeight: 34
                        Shape { anchors.fill: parent; kind: "burst"; color: toast.error ? Theme.error : Theme.secondaryContainer }
                        Icon { anchors.centerIn: parent; name: toast.error ? "priority_high" : "check"; size: 17; color: toast.error ? Theme.surface : Theme.inkSecondaryContainer }
                    }
                    Text { text: toast.text; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; Layout.maximumWidth: 520; elide: Text.ElideRight }
                    IconButton {
                        visible: toast.undoable
                        implicitHeight: 40
                        label: "Undo"; active: true
                        onClicked: { Fs.undo(); toast.opacity = 0; }
                    }
                }
            }
        }

        InfoPanel {
            id: infoPanel
            property real reveal: root.infoOpen ? 1 : 0
            Behavior on reveal { Anim { kind: "spatial" } }
            visible: reveal > 0
            opacity: Math.min(1, reveal)
            transform: Translate { x: (1 - Math.min(1, infoPanel.reveal)) * 40 }
            Layout.fillHeight: true
            tab: root.tab
            onOpenItem: (it) => root.activate(it)
        }
    }

    // ---- list header: large title, filters, sort ----
    Component {
        id: headerComp
        Item {
            id: header
            readonly property bool narrow: width < 760
            width: parent ? parent.width : 0
            implicitHeight: 92
            RowLayout {
                // Title lines up with the first tile, the sort button with the last column
                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 28; rightMargin: 24 }
                spacing: 16
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text {
                            // Shrinks with an ellipsis instead of pushing the filter/sort buttons out of the window
                            // Grows to its full width (+2 px rounding slack, or it ellipsizes at full width) and is the
                            // one thing that shrinks when the window is narrow: layouts only shrink fillWidth items
                            Layout.fillWidth: true
                            Layout.preferredWidth: implicitWidth + 2
                            Layout.maximumWidth: implicitWidth + 2
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            text: root.tab ? (root.tab.inTrash ? "Trash" : root.tab.name) : ""
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 34; font.weight: 700; font.letterSpacing: -0.4
                        }
                        Icon { name: "star"; filled: true; size: 20; color: Theme.tertiary; rotation: 12; Layout.alignment: Qt.AlignTop }
                        Item { Layout.fillWidth: true }
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: root.tab ? (root.tab.query ? root.tab.items.length + " results for “" + root.tab.query + "”"
                                         : root.tab.folders.length + (root.tab.folders.length === 1 ? " folder · " : " folders · ") + root.tab.files.length + (root.tab.files.length === 1 ? " file" : " files")) : ""
                        color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13
                    }
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    visible: !header.narrow
                    implicitWidth: chips.implicitWidth + 8; implicitHeight: 44; radius: 22
                    color: Theme.surfaceMid
                    Row {
                        id: chips
                        anchors.centerIn: parent
                        spacing: 4
                        Repeater {
                            model: [["all", "All"], ["image", "Images"], ["video", "Videos"], ["doc", "Docs"]]
                            delegate: IconButton {
                                required property var modelData
                                implicitHeight: 36
                                label: modelData[1]
                                active: root.tab && root.tab.filter === modelData[0]
                                bg: active ? Theme.secondaryContainer : (containsMouse ? Theme.hover : "transparent")
                                fg: active ? Theme.inkSecondaryContainer : Theme.textDim
                                onClicked: root.tab.filter = modelData[0]
                            }
                        }
                    }
                }
                IconButton {
                    id: filterBtn
                    visible: header.narrow
                    implicitHeight: 44
                    icon: "filter_list"; tip: "Filter"
                    active: root.tab && root.tab.filter !== "all"
                    onClicked: {
                        const p = filterBtn.mapToItem(root, -150, 48);
                        const f = [["all", "All"], ["image", "Images"], ["video", "Videos"], ["doc", "Docs"]];
                        root.showMenu(p.x, p.y, [], f.map(x => ({ icon: root.tab.filter === x[0] ? "check" : "", label: x[1], action: () => root.tab.filter = x[0] })));
                    }
                }
                IconButton {
                    id: sortBtn
                    implicitHeight: 44
                    icon: root.tab && root.tab.sortDesc ? "arrow_downward" : "arrow_upward"
                    label: !header.narrow && root.tab ? ({ name: "Name", modified: "Modified", size: "Size", kind: "Kind" })[root.tab.sortKey] : ""
                    bg: containsMouse ? Theme.hover : "transparent"
                    Rectangle { anchors.fill: parent; radius: height / 2; color: "transparent"; border.width: 1; border.color: Theme.outlineVariant }
                    onClicked: {
                        const p = sortBtn.mapToItem(root, -120, 48);
                        const s = [["name", "Name"], ["modified", "Modified"], ["size", "Size"], ["kind", "Kind"]];
                        root.showMenu(p.x, p.y, [], s.map(x => ({ icon: root.tab.sortKey === x[0] ? (root.tab.sortDesc ? "arrow_downward" : "arrow_upward") : "", label: x[1], action: () => root.setSort(x[0]) })));
                    }
                }
            }
        }
    }

    // ---- scripting / testing: qs -p <dir>/shell.qml ipc call files <fn> <arg> ----
    IpcHandler {
        target: "files"
        function go(path: string): void { root.goTo(path); }
        function view(mode: string): void { root.tab.viewMode = mode; }
        function select(names: string): void {
            const want = names.split("|"), s = {};
            root.tab.items.forEach(it => { if (want.indexOf(it.name) >= 0) s[it.path] = true; });
            root.tab.selection = s;
            root.tab.current = Object.keys(s)[0] ?? "";
        }
        function menu(kind: string): void {
            const it = root.tab.selectedItems[0];
            if (kind === "item" && it) root.itemMenu(it, root.width * 0.45, root.height * 0.3);
            else root.backgroundMenu(root.width * 0.45, root.height * 0.3);
        }
        function sub(index: int): void { menuLoader.item?.openSub(index); }
        function info(open: bool): void { root.infoOpen = open; }
        function rename(): void { root.startRename(); }
        function toast(text: string): void { Fs.toast(text, true); }
        function zoom(z: real): void { root.zoom = z; }
        function scroll(px: int): void { const l = root.tab.viewMode === "details" ? detailsView : iconView; l.contentY = l.originY - l.topMargin + px; }
        function menuAt(xy: string): void { const p = xy.split(","); root.backgroundMenu(Number(p[0]), Number(p[1])); }
    }

    // ---- menu overlay ----
    MouseArea {
        anchors.fill: parent
        visible: root.menuOpen
        acceptedButtons: Qt.AllButtons
        onPressed: root.menuOpen = false
    }
    Loader {
        id: menuLoader
        active: root.menuOpen
        x: Math.max(8, Math.min(root.menuX, root.width - 300 - 8 - (item && item.subIndex >= 0 ? 258 : 0)))
        y: Math.max(8, Math.min(root.menuY, root.height - (item ? item.height : 0) - 8))
        sourceComponent: Menu {
            origin: Qt.point(Math.max(0, Math.min(root.menuX - menuLoader.x, 300)), Math.max(0, root.menuY - menuLoader.y))
            quick: root.menuQuick
            entries: root.menuEntries
            onDone: { root.menuOpen = false; view.forceActiveFocus(); }
        }
        onLoaded: item.forceActiveFocus()
    }
}
