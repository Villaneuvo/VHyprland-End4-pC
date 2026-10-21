import QtQuick
import QtQuick.Layouts

// Glass sidebar, GNOME Files 47 order: Home, Recent, Starred, Network, Trash; pinned folders (GTK's bookmarks);
// Devices; a disk meter. Collapses to an icon rail when `rail` is on.
Rectangle {
    id: root
    required property var tab
    property bool rail: false
    signal open(string path)
    signal openDolphin(string path)
    signal openAddress(string address)              // a network pin: connect, then open
    signal pinMenu(string path, real x, real y)    // right-click on a pinned folder (x, y in the sidebar)
    property string renamingPin: ""                 // pinned folder whose label is being edited inline
    Component.onCompleted: Fs.checkPins()
    // Asks the disk, not the last check: a drive can come back without the device list changing (LUKS, network)
    // A folder dropped between pins: pin it there (only folders: a test on disk first)
    function pinDrop(path, at) {
        Fs.dragTarget = "";
        if (!path) return Fs.toast("Only folders can be pinned", false);
        Fs.run(["test", "-d", path], (t, notDir) => {
            if (notDir) return Fs.toast("Only folders can be pinned", false);
            Fs.pin(path, at);
            Fs.toast("Pinned “" + path.slice(path.lastIndexOf("/") + 1) + "”", false);
        });
    }
    function openPin(pin) {
        if (pin.network) return root.openAddress(pin.uri);
        Fs.run(["test", "-d", pin.path], (t, missing) => {
            if (missing) Fs.toast("This folder isn't available", false);
            else root.open(pin.path);
            if (!missing !== pin.exists) Fs.checkPins();
        });
    }
    property Item activeRow: null
    onActivePlaceChanged: if (activePlace === "") activeRow = null

    implicitWidth: rail ? 72 : 248
    radius: Theme.rPanel
    color: Theme.chrome
    Sheen { radius: root.radius; tint: 0.08 }
    Behavior on implicitWidth { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    readonly property var places: [
        { name: "Home", icon: "home", path: Fs.home },
        { name: "Recent", icon: "schedule", path: Fs.recentPath },
        { name: "Starred", icon: "star", path: Fs.starredPath },
        { name: "Network", icon: "language", path: "network:" },
        { name: "Trash", icon: "delete", path: Fs.trashDir, badge: Fs.trashCount }
    ]

    // The place you're in: the deepest place, pin or server that contains the current folder
    readonly property string activePlace: {
        if (tab.place === "network") return "network:";
        let best = "";
        for (const p of places.concat(Fs.pins, Fs.netMounts))
            if (p.path && (tab.path === p.path || tab.path.startsWith(p.path + "/")) && p.path.length > best.length) best = p.path;
        return best;
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: root.rail ? 10 : 10
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Item {
            width: parent.width
            implicitHeight: col.implicitHeight
            // The active place's pill: one rectangle that glides between rows instead of each row drawing its own
            Rectangle {
                visible: root.activeRow !== null && root.activeRow.visible
                x: (root.activeRow ? root.activeRow.x : 0) + (root.rail ? 4 : 0)
                y: root.activeRow ? root.activeRow.y : 0
                width: (root.activeRow ? root.activeRow.width : 0) - (root.rail ? 8 : 0)
                height: root.activeRow ? root.activeRow.height : 0
                radius: height / 2
                color: Theme.primaryContainer
                Behavior on y { Anim { kind: "fastSpatial" } }
            }
        ColumnLayout {
            id: col
            width: parent.width
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: root.rail ? 0 : 6
                Layout.bottomMargin: 12
                spacing: 10
                Item {
                    implicitWidth: 36; implicitHeight: 36
                    Layout.alignment: root.rail ? Qt.AlignHCenter : Qt.AlignLeft
                    Shape { anchors.fill: parent; kind: "flower"; color: Theme.primary }
                    Icon { anchors.centerIn: parent; name: "folder_open"; size: 19; color: Theme.inkPrimary; filled: true }
                }
                ColumnLayout {
                    visible: !root.rail
                    spacing: 0
                    Text { text: "Files"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: 650 }
                    Text { text: Fs.home.slice(Fs.home.lastIndexOf("/") + 1); color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                }
            }

            SectionLabel { text: "Places"; visible: !root.rail }
            Repeater {
                model: root.places
                delegate: PlaceRow {
                    required property var modelData
                    Layout.fillWidth: true
                    icon: modelData.icon; label: modelData.name; badge: modelData.badge ?? 0
                    active: modelData.path !== "" && modelData.path === root.activePlace
                    rail: root.rail
                    dropPath: modelData.path.startsWith("/") ? modelData.path : ""   // Home, Trash (not Recent, Starred, Network)
                    onClicked: root.open(modelData.path)
                }
            }

            Rectangle {
                visible: Fs.pins.length > 0
                Layout.fillWidth: true
                Layout.leftMargin: 14; Layout.rightMargin: 14; Layout.topMargin: 6; Layout.bottomMargin: 6
                implicitHeight: 1
                color: Theme.outlineVariant
            }
            Repeater {
                model: Fs.pins
                delegate: PlaceRow {
                    id: pinRow
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    icon: modelData.network ? Fs.netIcon(modelData.uri) : Fs.pinIcon(modelData.path, Fs.dirs); label: modelData.name; rail: root.rail
                    dim: !modelData.exists
                    renaming: root.renamingPin === modelData.key
                    active: modelData.path !== "" && modelData.path === root.activePlace
                    dropPath: modelData.network ? Fs.netPathOf(modelData.uri, Fs.netMounts) : modelData.exists ? modelData.path : ""
                    PinGap { at: pinRow.index; y: -6 }
                    PinGap { at: pinRow.index + 1; y: pinRow.height - 6; visible: pinRow.index === Fs.pins.length - 1 }
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (m) => {
                        if (m.button === Qt.RightButton) { const p = mapToItem(root, m.x, m.y); root.pinMenu(modelData.key, p.x, p.y); }
                        else root.openPin(modelData);
                    }
                    // Typing the default name back (folder name, or "dir on host") means no label
                    onRenamed: (name) => { root.renamingPin = ""; Fs.renamePin(modelData.key, name === (modelData.network ? Fs.netPinName(modelData.uri, "") : modelData.path.slice(modelData.path.lastIndexOf("/") + 1)) ? "" : name); }
                    onRenameCancelled: root.renamingPin = ""
                }
            }

            SectionLabel { text: "Devices"; visible: !root.rail && Fs.devices.length > 0; Layout.topMargin: 14 }
            Repeater {
                model: Fs.devices
                delegate: PlaceRow {
                    required property var modelData
                    Layout.fillWidth: true
                    icon: "usb"; label: modelData.label; rail: root.rail
                    active: modelData.mount !== "" && root.tab.path.startsWith(modelData.mount)
                    trailingIcon: modelData.mount ? "eject" : ""
                    onTrailingClicked: Fs.eject(modelData.dev)
                    dropPath: modelData.mount
                    onClicked: modelData.mount ? root.open(modelData.mount) : Fs.mount(modelData.dev, () => {})
                }
            }

            SectionLabel { text: "Connected"; visible: !root.rail && Fs.netMounts.length > 0; Layout.topMargin: 14 }
            Repeater {
                model: Fs.netMounts
                delegate: PlaceRow {
                    required property var modelData
                    Layout.fillWidth: true
                    icon: Fs.netIcon(modelData.uri); label: modelData.name; rail: root.rail
                    active: modelData.path === root.activePlace
                    trailingIcon: modelData.canUnmount ? "eject" : ""; trailingTip: "Unmount"
                    onTrailingClicked: Fs.unmount(modelData.uri, false)
                    dropPath: modelData.path
                    onClicked: root.open(modelData.path)
                }
            }

            Item { implicitHeight: 12 }
            Rectangle {
                visible: !root.rail && Fs.diskLine !== ""
                Layout.fillWidth: true
                implicitHeight: diskCol.implicitHeight + 24
                radius: 14
                color: Theme.alpha(Theme.surfaceLowest, 0.45)
                ColumnLayout {
                    id: diskCol
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
                    spacing: 8
                    RowLayout {
                        Text { text: "Internal disk"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: 600; Layout.fillWidth: true }
                        Text { text: Math.round(Fs.diskUsed * 100) + "%"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13 }
                    }
                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: 8; radius: 4; color: Theme.alpha(Theme.inkPrimaryContainer, 0.12)
                        Rectangle { width: parent.width * Fs.diskUsed; height: parent.height; radius: 4; color: Theme.primary }
                    }
                    Text { text: Fs.diskLine; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                }
            }
        }
        }
    }

    component SectionLabel: Text {
        Layout.leftMargin: 12; Layout.topMargin: 10; Layout.bottomMargin: 4
        color: Theme.textDim
        font.family: Theme.font; font.pixelSize: 12; font.weight: 600; font.letterSpacing: 0.4
    }

    // Between two pins: a folder dropped here is pinned at that spot (a line marks it)
    component PinGap: DropArea {
        property int at
        x: 0; width: parent ? parent.width : 0; height: 12; z: 2
        keys: ["text/uri-list"]
        onEntered: (drag) => { if (drag.urls.length === 1) Fs.dragTarget = "pin:" + at; else drag.accepted = false; }
        onExited: if (Fs.dragTarget === "pin:" + at) Fs.dragTarget = ""
        onDropped: (drop) => { root.pinDrop(Fs.dropPaths(drop.urls).paths[0] ?? "", at); drop.accept(Qt.LinkAction); }
        Rectangle {
            visible: Fs.dragTarget === "pin:" + parent.at
            anchors.verticalCenter: parent.verticalCenter
            x: 14; width: parent.width - 28; height: 2; radius: 1
            color: Theme.primary
        }
    }
    component PlaceRow: MouseArea {
        id: row
        onActiveChanged: if (active) root.activeRow = row
        Component.onCompleted: if (active) root.activeRow = row
        property string icon
        property string label
        property int badge: 0
        property bool active: false
        property bool rail: false
        property string trailingIcon: ""
        property string trailingTip: "Eject"
        property bool dim: false            // a pinned folder that isn't there (unmounted drive)
        property bool renaming: false
        property string dropPath: ""        // drops go into this folder (Fs.trashDir: to Trash); "" takes none
        readonly property bool dropHover: dropPath !== "" && Fs.dragTarget === dropPath
        signal trailingClicked()
        signal renamed(string name)
        signal renameCancelled()
        opacity: dim ? 0.45 : 1
        implicitHeight: Theme.target
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: row.rail ? 4 : 0; anchors.rightMargin: row.rail ? 4 : 0
            radius: height / 2
            color: !row.active && row.containsMouse ? Theme.hover : "transparent"
            border.width: row.dropHover ? 2 : 0
            border.color: Theme.primary
        }
        DropArea {
            anchors.fill: parent
            enabled: row.dropPath !== ""
            keys: ["text/uri-list"]
            onEntered: (drag) => { if (Fs.dragPaths.indexOf(row.dropPath) >= 0) drag.accepted = false; else Fs.dragTarget = row.dropPath; }
            onExited: if (Fs.dragTarget === row.dropPath) Fs.dragTarget = ""
            onDropped: (drop) => { Fs.dropOn(row.dropPath, drop.urls); drop.accept(Qt.CopyAction); }
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: row.rail ? 0 : 14
            anchors.rightMargin: 4
            spacing: 12
            Item {
                implicitWidth: row.rail ? row.width - 4 : 20; implicitHeight: 20
                Icon { anchors.centerIn: parent; name: row.icon; filled: row.active; color: row.active ? Theme.inkPrimaryContainer : Theme.text }
                Item {
                    visible: row.rail && row.badge > 0
                    x: parent.width / 2 + 4; y: -8; width: 20; height: 20
                    Shape { anchors.fill: parent; kind: "burst"; color: Theme.primary }
                    Text { anchors.centerIn: parent; text: row.badge > 99 ? "99" : row.badge; color: Theme.inkPrimary; font.family: Theme.font; font.pixelSize: 10; font.weight: 700 }
                }
            }
            Loader {
                active: row.renaming && !row.rail
                visible: active
                Layout.fillWidth: true
                sourceComponent: RenameField {
                    text: row.label; isDir: true
                    onAccepted: (name) => row.renamed(name)
                    onCancelled: row.renameCancelled()
                }
            }
            Text {
                visible: !row.rail && !row.renaming
                Layout.fillWidth: true
                text: row.label
                textFormat: Text.PlainText   // pin labels and folder names are file-derived
                elide: Text.ElideRight
                color: row.active ? Theme.inkPrimaryContainer : Theme.text
                font.family: Theme.font; font.pixelSize: 14; font.weight: row.active ? 600 : 450
            }
            Text {
                visible: !row.rail && row.badge > 0
                text: row.badge
                color: Theme.textDim
                font.family: Theme.font; font.pixelSize: 12
                Layout.rightMargin: 10
            }
            IconButton {
                visible: !row.rail && row.trailingIcon !== ""
                icon: row.trailingIcon; iconSize: 18; tip: row.trailingTip
                implicitWidth: 36; implicitHeight: 36
                onClicked: row.trailingClicked()
            }
        }
        Accessible.role: Accessible.Link
        Accessible.name: label
    }
}
