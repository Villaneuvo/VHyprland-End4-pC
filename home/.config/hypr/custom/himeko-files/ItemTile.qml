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
    property int appearOrder: -1          // position among the first tiles of a freshly opened folder
    property real fade: 1
    readonly property bool selected: tab.selection[item.path] === true
    readonly property bool focused: tab.current === item.path
    readonly property bool cut: Fs.clip.mode === "move" && Fs.clip.paths.indexOf(item.path) >= 0
    readonly property bool dropHover: Fs.dragTarget === item.path
    property int dragCount: 0              // shown on the tile while its drag image is taken (several items)
    readonly property bool special: item.isDir && Object.values(Fs.dirs).indexOf(item.path) >= 0
    signal activated()
    signal menu(real x, real y)
    signal renamed(string name)
    signal renameCancelled()

    implicitHeight: wide ? 72 : thumbHeight + 12 + 44
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    opacity: (cut ? 0.5 : 1) * fade
    scale: containsMouse ? 1.02 : 1
    Behavior on scale { Anim { kind: "effects" } }
    transform: Translate { id: lift }
    // The first 24 tiles of a folder that just opened fade in and rise 8 px, 15 ms apart
    Component.onCompleted: {
        if (!Theme.animate || appearOrder < 0 || appearOrder >= 24 || Date.now() - tab.loadedAt > 600) return;
        fade = 0; lift.y = 8;
        appear.start();
    }
    SequentialAnimation {
        id: appear
        PauseAnimation { duration: root.appearOrder * 15 }
        ParallelAnimation {
            Anim { target: root; property: "fade"; to: 1; kind: "enter" }
            Anim { target: lift; property: "y"; to: 0; kind: "enter" }
        }
    }

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
        border.width: root.dropHover ? 2 : root.focused && !root.selected ? 1 : 0
        border.color: root.dropHover ? Theme.primary : Theme.outline
    }

    // Starred: a small star at the top left
    Item {
        z: 2
        visible: Fs.isStarred(root.item.path)
        x: 4; y: 4; width: 24; height: 24
        Shape { anchors.fill: parent; kind: "cookie"; color: Theme.surfaceHighest }
        Icon { anchors.centerIn: parent; name: "star"; filled: true; size: 16; color: Theme.primary }
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
                border.width: 3
                opacity: root.selected ? 1 : 0
                Behavior on opacity { Anim { kind: "effects" } }
                border.color: Theme.primary
            }
            Thumb { anchors.fill: parent; item: root.item }
            Item {
                scale: root.selected ? 1 : 0
                visible: scale > 0
                Behavior on scale { Anim { kind: "fastSpatial" } }
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
                text: root.tab.place === "recent" && root.item.used ? Fs.openedText(root.item.used)
                    : Fs.size(root.item.size) + " · " + Fs.date(root.item.modified)
                elide: Text.ElideRight
                color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12
            }
        }
    }

    component NameText: Text {
        text: root.item.name
        textFormat: Text.PlainText   // names can look like markup ("<b>")
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

    // ---- drag: the selection (this one included) as file URIs, to folders, the sidebar, tabs or other apps.
    // The drag itself runs on Browser's proxy (Fs.startDrag): spring-open may destroy this item mid-drag
    DragHandler {
        id: dragger
        target: null
        acceptedButtons: Qt.LeftButton
        enabled: !root.renaming
        onActiveChanged: {
            if (!active) return;   // the drag ends on the proxy (dragFinished), not here
            if (!root.selected) root.tab.select(root.item, 0);
            const paths = root.tab.paths();
            root.dragCount = paths.length > 1 ? paths.length : 0;
            root.grabToImage((r) => { root.dragCount = 0; if (dragger.active) Fs.startDrag(paths, r.url); });   // not after a quick flick
        }
    }
    // A folder takes drops: it lights up, and opens after a short hover (Browser's spring timer)
    DropArea {
        anchors.fill: parent
        enabled: root.item.isDir && !root.tab.inTrash   // nothing goes into folders inside Trash
        keys: ["text/uri-list"]
        onEntered: (drag) => { if (Fs.dragPaths.indexOf(root.item.path) >= 0) drag.accepted = false; else Fs.dragTarget = root.item.path; }
        onExited: if (Fs.dragTarget === root.item.path) Fs.dragTarget = ""
        onDropped: (drop) => { Fs.dropOn(root.item.path, drop.urls); drop.accept(Qt.CopyAction); }
    }
    // How many items a drag carries, on the drag image
    Rectangle {
        visible: root.dragCount > 0
        z: 3
        x: 6; y: 6; width: 26; height: 26; radius: 13
        color: Theme.primary
        Text { anchors.centerIn: parent; text: root.dragCount; color: Theme.inkPrimary; font.family: Theme.font; font.pixelSize: 12; font.weight: 700 }
    }

    Accessible.role: Accessible.ListItem
    Accessible.name: item.name + (selected ? ", selected" : "")
}
