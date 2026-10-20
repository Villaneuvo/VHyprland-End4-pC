import QtQuick
import QtQuick.Layouts

// Details view: sortable columns, 48 px rows, selected row in primary container + cookie check.
ListView {
    id: root
    required property var tab
    property string renamingPath: ""
    property Component headerComponent
    signal activated(var item)
    signal itemMenu(var item, real x, real y)
    signal backgroundMenu(real x, real y)
    signal renamed(var item, string name)
    signal renameCancelled()

    property real pad: 16
    readonly property var cols: [
        { key: "name", label: "Name", w: 0 },
        { key: "size", label: "Size", w: 110 },
        { key: "modified", label: "Modified", w: 170 },
        tab.virtual ? { key: "location", label: "Location", w: 200 } : { key: "kind", label: "Kind", w: 130 }
    ]
    readonly property var rows: tab.items
    // A rebuilt listing (a file added, the sort changed) keeps its scroll position; another folder starts at the top.
    // The model is set here, not bound: ListView jumps to the top on a new model before any handler sees it.
    property string shownPath: ""
    onRowsChanged: show()
    Component.onCompleted: show()
    function show() {
        const y = contentY - originY, same = tab.path === shownPath;
        model = rows;
        shownPath = tab.path;
        if (!same) return;
        forceLayout();
        contentY = originY + y;
        returnToBounds();
    }
    clip: false
    boundsBehavior: Flickable.StopAtBounds
    reuseItems: true
    header: Column {
        width: root.width
        Loader { width: parent.width; sourceComponent: root.headerComponent }
        RowLayout {
            x: root.pad
            width: root.width - 2 * root.pad
            height: 40
            spacing: 0
            Repeater {
                model: root.cols
                delegate: MouseArea {
                    required property var modelData
                    Layout.fillWidth: modelData.w === 0
                    Layout.preferredWidth: modelData.w || 100
                    Layout.fillHeight: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.tab.sortKey === modelData.key) root.tab.sortDesc = !root.tab.sortDesc;
                        else { root.tab.sortKey = modelData.key; root.tab.sortDesc = modelData.key === "modified" || modelData.key === "size"; }
                    }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        x: parent.Layout.fillWidth ? 14 : 0
                        spacing: 4
                        Text {
                            text: modelData.label
                            color: root.tab.sortKey === modelData.key ? Theme.text : Theme.textDim
                            font.family: Theme.font; font.pixelSize: 12; font.weight: 600; font.letterSpacing: 0.3
                        }
                        Icon {
                            visible: root.tab.sortKey === modelData.key
                            name: root.tab.sortDesc ? "arrow_downward" : "arrow_upward"
                            size: 14
                        }
                    }
                }
            }
        }
    }
    footer: Item { width: 1; height: 96 }

    MouseArea {
        z: -1
        width: root.width; height: Math.max(root.height, root.contentHeight + root.topMargin)
        y: -root.topMargin
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: (e) => {
            root.forceActiveFocus();
            root.tab.clearSelection();
            if (e.button === Qt.RightButton) { const p = mapToItem(root, e.x, e.y); root.backgroundMenu(p.x, p.y); }
        }
    }

    delegate: MouseArea {
        id: row
        required property var modelData
        required property int index
        property real fade: 1
        readonly property bool selected: root.tab.selection[modelData.path] === true
        readonly property bool cut: Fs.clip.mode === "move" && Fs.clip.paths.indexOf(modelData.path) >= 0
        readonly property string kind: Fs.kindOf(modelData)
        width: root.width // ListView pins delegates at x = 0: pad inside instead
        height: 48
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        opacity: (cut ? 0.5 : 1) * fade
        transform: Translate { id: rowLift }
        Component.onCompleted: {
            if (!Theme.animate || index >= 24 || Date.now() - root.tab.loadedAt > 600) return;
            fade = 0; rowLift.y = 8;
            rowAppear.start();
        }
        SequentialAnimation {
            id: rowAppear
            PauseAnimation { duration: row.index * 15 }
            ParallelAnimation {
                Anim { target: row; property: "fade"; to: 1; kind: "enter" }
                Anim { target: rowLift; property: "y"; to: 0; kind: "enter" }
            }
        }
        onPressed: (e) => {
            if (e.button === Qt.RightButton) {
                if (!selected) root.tab.select(modelData, 0);
                const p = mapToItem(root, e.x, e.y);
                root.itemMenu(modelData, p.x, p.y);
            } else if (!(selected && e.modifiers === 0)) {
                root.tab.select(modelData, e.modifiers);
            }
        }
        onClicked: (e) => { if (e.button === Qt.LeftButton && e.modifiers === 0 && root.tab.selectedCount > 1) root.tab.select(modelData, 0); }
        onDoubleClicked: (e) => { if (e.button === Qt.LeftButton) root.activated(modelData); }

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: root.pad; anchors.rightMargin: root.pad
            radius: Theme.rRow
            color: row.selected ? Theme.primaryContainer : (row.containsMouse ? Theme.hover : "transparent")
            border.width: root.tab.current === row.modelData.path && !row.selected ? 1 : 0
            border.color: Theme.outline
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.pad; anchors.rightMargin: root.pad
            spacing: 0
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                spacing: 12
                Thumb { item: row.modelData; implicitWidth: 32; implicitHeight: 32; radius: 9; iconSize: 17 }
                Text {
                    visible: root.renamingPath !== row.modelData.path
                    Layout.fillWidth: true
                    text: row.modelData.name
                    textFormat: Text.PlainText   // names can look like markup ("<b>")
                    elide: Text.ElideMiddle
                    readonly property bool starred: Fs.isStarred(row.modelData.path)
                    rightPadding: starred ? 24 : 0
                    Icon { visible: parent.starred; x: parent.contentWidth + 6; anchors.verticalCenter: parent.verticalCenter; name: "star"; filled: true; size: 16; color: Theme.primary }
                    color: row.selected ? Theme.inkPrimaryContainer : Theme.text
                    font.family: Theme.font; font.pixelSize: 14; font.weight: row.selected ? 650 : 500
                }
                Loader {
                    active: root.renamingPath === row.modelData.path
                    visible: active
                    Layout.fillWidth: true
                    sourceComponent: RenameField {
                        text: row.modelData.name
                        isDir: row.modelData.isDir
                        onAccepted: (name) => root.renamed(row.modelData, name)
                        onCancelled: root.renameCancelled()
                    }
                }
                Item {
                    scale: row.selected ? 1 : 0
                    visible: scale > 0
                    Behavior on scale { Anim { kind: "fastSpatial" } }
                    implicitWidth: 20; implicitHeight: 20
                    Layout.rightMargin: 8
                    Shape { anchors.fill: parent; kind: "cookie"; color: Theme.primary }
                    Icon { anchors.centerIn: parent; name: "check"; size: 13; color: Theme.inkPrimary; font.variableAxes: ({ "wght": 700 }) }
                }
            }
            Repeater {
                model: [
                    row.modelData.isDir ? Fs.countLabel(root.tab.countOf(row.modelData.path)) : Fs.size(row.modelData.size),
                    Fs.date(row.modelData.modified),
                    root.tab.virtual ? Fs.displayPath(Fs.parentOf(row.modelData.path)) : Fs.labelOf(row.kind, row.modelData.suffix)
                ]
                delegate: Text {
                    required property var modelData
                    required property int index
                    Layout.preferredWidth: root.cols[index + 1].w
                    text: modelData
                    textFormat: Text.PlainText   // Location is a path
                    elide: Text.ElideMiddle
                    color: row.selected ? Theme.inkPrimaryContainer : Theme.textDim
                    font.family: Theme.font; font.pixelSize: 13
                }
            }
        }
        Accessible.role: Accessible.Row
        Accessible.name: modelData.name + (selected ? ", selected" : "")
    }
}
