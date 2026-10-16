import QtQuick
import QtQuick.Layouts

// An item in the icons view. Folders are wide tiles, files are square previews.
// Selected = accent ring + cookie check (shapes speak state).
MouseArea {
    id: root
    required property var item
    required property var tab
    property bool wide: item.isDir
    property real thumbHeight: 104
    property bool renaming: false
    readonly property bool selected: tab.selection[item.path] === true
    readonly property bool focused: tab.current === item.path
    readonly property bool cut: Fs.clip.mode === "move" && Fs.clip.paths.indexOf(item.path) >= 0
    readonly property bool special: item.isDir && Object.values(Fs.dirs).indexOf(item.path) >= 0
    signal activated()
    signal menu(real x, real y)
    signal renamed(string name)
    signal renameCancelled()

    implicitHeight: wide ? 72 : thumbHeight + 12 + 44
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    opacity: cut ? 0.5 : 1

    onPressed: (e) => {
        if (e.button === Qt.RightButton) {
            if (!selected) tab.select(item, 0);
            menu(e.x, e.y);
        } else if (!(selected && e.modifiers === 0)) {
            tab.select(item, e.modifiers);
        }
    }
    onClicked: (e) => { if (e.button === Qt.LeftButton && e.modifiers === 0 && tab.selectedCount > 1) tab.select(item, 0); }
    onDoubleClicked: (e) => { if (e.button === Qt.LeftButton) activated(); }

    Rectangle {
        anchors.fill: parent
        radius: root.wide ? 20 : Theme.rTile
        color: root.selected ? Theme.alpha(Theme.primary, 0.12)
             : root.wide ? (root.containsMouse ? Theme.surfaceHighest : Theme.surfaceHigh)
             : (root.containsMouse ? Theme.hover : "transparent")
        border.width: root.focused && !root.selected ? 1 : 0
        border.color: Theme.outline
    }

    // ---- wide (folder) ----
    RowLayout {
        visible: root.wide
        anchors.fill: parent
        anchors.leftMargin: 14; anchors.rightMargin: 14
        spacing: 12
        Item {
            implicitWidth: 44; implicitHeight: 44
            Shape { anchors.fill: parent; visible: root.special; kind: "flower"; color: root.selected ? Theme.primary : Theme.secondaryContainer }
            Rectangle { anchors.fill: parent; visible: !root.special; radius: 14; color: root.selected ? Theme.primary : Theme.secondaryContainer }
            Icon { anchors.centerIn: parent; name: "folder"; filled: true; size: 21; color: root.selected ? Theme.inkPrimary : Theme.inkSecondaryContainer }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            NameText { visible: !root.renaming; Layout.fillWidth: true }
            Loader { active: root.renaming; visible: active; Layout.fillWidth: true; sourceComponent: renameField }
            Text { text: Fs.countLabel(root.tab.countOf(root.item.path)); color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
        }
    }

    // ---- square (file) ----
    ColumnLayout {
        visible: !root.wide
        anchors.fill: parent
        anchors.margins: 6
        spacing: 8
        Item {
            Layout.fillWidth: true
            implicitHeight: root.thumbHeight
            Rectangle {
                anchors.fill: parent; anchors.margins: -3
                radius: Theme.rThumb + 3
                color: "transparent"
                border.width: root.selected ? 3 : 0
                border.color: Theme.primary
            }
            Thumb { anchors.fill: parent; item: root.item }
            Item {
                visible: root.selected
                anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 6
                width: 28; height: 28
                Shape { anchors.fill: parent; kind: "cookie"; color: Theme.primary }
                Icon { anchors.centerIn: parent; name: "check"; size: 17; color: Theme.inkPrimary; font.variableAxes: ({ "wght": 700 }) }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 6; Layout.rightMargin: 6
            spacing: 0
            NameText { visible: !root.renaming; Layout.fillWidth: true }
            Loader { active: root.renaming; visible: active; Layout.fillWidth: true; sourceComponent: renameField }
            Text {
                Layout.fillWidth: true
                text: Fs.size(root.item.size) + " · " + Fs.date(root.item.modified)
                elide: Text.ElideRight
                color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12
            }
        }
    }

    component NameText: Text {
        text: root.item.name
        elide: Text.ElideMiddle
        color: Theme.text
        font.family: Theme.font; font.pixelSize: 13; font.weight: 600
    }

    Component {
        id: renameField
        RenameField {
            text: root.item.name
            isDir: root.item.isDir
            onAccepted: (name) => root.renamed(name)
            onCancelled: root.renameCancelled()
        }
    }

    Accessible.role: Accessible.ListItem
    Accessible.name: item.name + (selected ? ", selected" : "")
}
