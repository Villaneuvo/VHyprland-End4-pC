import QtQuick
import QtQuick.Layouts

// Glass sidebar: Places, Devices, a disk meter. Collapses to an icon rail when `rail` is on.
Rectangle {
    id: root
    required property var tab
    property bool rail: false
    signal open(string path)
    signal openDolphin(string path)
    property Item activeRow: null
    onActivePlaceChanged: if (activePlace === "") activeRow = null

    implicitWidth: rail ? 72 : 248
    radius: Theme.rPanel
    color: Theme.chrome
    Sheen { radius: root.radius; tint: 0.08 }
    Behavior on implicitWidth { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    readonly property var places: [
        { name: "Home", icon: "home", path: Fs.home },
        { name: "Desktop", icon: "desktop_windows", path: Fs.dirs.desktop ?? "" },
        { name: "Documents", icon: "description", path: Fs.dirs.documents ?? "" },
        { name: "Downloads", icon: "download", path: Fs.dirs.download ?? "" },
        { name: "Pictures", icon: "image", path: Fs.dirs.pictures ?? "" },
        { name: "Music", icon: "music_note", path: Fs.dirs.music ?? "" },
        { name: "Videos", icon: "movie", path: Fs.dirs.videos ?? "" },
        { name: "Trash", icon: "delete", path: Fs.trashDir, badge: Fs.trashCount }
    ].filter(p => p.path && (p.path !== Fs.home || p.name === "Home"))

    // The place you're in: the deepest place that contains the current folder
    readonly property string activePlace: {
        let best = "";
        for (const p of places) if ((tab.path === p.path || tab.path.startsWith(p.path + "/")) && p.path.length > best.length) best = p.path;
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
                    active: modelData.path === root.activePlace
                    rail: root.rail
                    onClicked: root.open(modelData.path)
                }
            }

            SectionLabel { text: "Devices"; visible: !root.rail && Fs.devices.length > 0 }
            Repeater {
                model: Fs.devices
                delegate: PlaceRow {
                    required property var modelData
                    Layout.fillWidth: true
                    icon: "usb"; label: modelData.label; rail: root.rail
                    active: modelData.mount !== "" && root.tab.path.startsWith(modelData.mount)
                    trailingIcon: modelData.mount ? "eject" : ""
                    onTrailingClicked: Fs.eject(modelData.dev)
                    onClicked: modelData.mount ? root.open(modelData.mount) : Fs.mount(modelData.dev, () => {})
                }
            }
            PlaceRow {
                Layout.fillWidth: true
                icon: "language"; label: "Network"; rail: root.rail
                onClicked: root.openDolphin("remote:/")
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
        signal trailingClicked()
        implicitHeight: Theme.target
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: row.rail ? 4 : 0; anchors.rightMargin: row.rail ? 4 : 0
            radius: height / 2
            color: !row.active && row.containsMouse ? Theme.hover : "transparent"
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
            Text {
                visible: !row.rail
                Layout.fillWidth: true
                text: row.label
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
                icon: row.trailingIcon; iconSize: 18; tip: "Eject"
                implicitWidth: 36; implicitHeight: 36
                onClicked: row.trailingClicked()
            }
        }
        Accessible.role: Accessible.Link
        Accessible.name: label
    }
}
