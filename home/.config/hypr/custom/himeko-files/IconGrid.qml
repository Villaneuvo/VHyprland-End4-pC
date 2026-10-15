import QtQuick
import QtQuick.Layouts

// Icons view: section labels, rows of wide folder tiles and rows of square file previews.
// Built as a ListView of rows so huge folders stay fast (only visible rows exist).
ListView {
    id: root
    required property var tab
    property real zoom: 1.0
    property string renamingPath: ""
    property Component headerComponent
    signal activated(var item)
    signal itemMenu(var item, real x, real y)
    signal backgroundMenu(real x, real y)
    signal renamed(var item, string name)
    signal renameCancelled()

    readonly property real gap: 14
    readonly property real usable: width - leftMargin - rightMargin
    readonly property int folderCols: Math.max(1, Math.floor((usable + gap) / (230 + gap)))
    readonly property real tileW: 150 * zoom
    readonly property int fileCols: Math.max(1, Math.floor((usable + gap) / (tileW + gap)))
    readonly property real thumbH: (usable - gap * (fileCols - 1)) / fileCols * 0.68

    function chunk(list, n) { const out = []; for (let i = 0; i < list.length; i += n) out.push(list.slice(i, i + n)); return out; }
    readonly property string filesLabel: {
        const f = tab.filter;
        if (f === "image") return "Images";
        if (f === "video") return "Videos";
        if (f === "doc") return "Documents";
        return tab.files.length > 0 && tab.files.every(it => Fs.kindOf(it) === "image") ? "Images" : "Files";
    }
    model: {
        const rows = [];
        if (tab.folders.length) {
            rows.push({ kind: "label", text: "Folders" });
            for (const r of chunk(tab.folders, folderCols)) rows.push({ kind: "folders", items: r });
        }
        if (tab.files.length) {
            rows.push({ kind: "label", text: filesLabel });
            for (const r of chunk(tab.files, fileCols)) rows.push({ kind: "files", items: r });
        }
        return rows;
    }

    clip: false
    spacing: 12
    boundsBehavior: Flickable.StopAtBounds
    reuseItems: true
    cacheBuffer: 600
    header: headerComponent
    footer: Item { width: 1; height: 96 }

    // Clicking empty space clears the selection; right-click there opens the folder menu
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

    delegate: Item {
        id: row
        required property var modelData
        width: root.usable
        x: root.leftMargin
        height: modelData.kind === "label" ? 26 : grid.implicitHeight
        Text {
            visible: row.modelData.kind === "label"
            anchors.bottom: parent.bottom
            text: row.modelData.text ?? ""
            color: Theme.textDim
            font.family: Theme.font; font.pixelSize: 13; font.weight: 600; font.letterSpacing: 0.3
        }
        GridLayout {
            id: grid
            visible: row.modelData.kind !== "label"
            width: parent.width
            columns: row.modelData.kind === "folders" ? root.folderCols : root.fileCols
            columnSpacing: root.gap
            rowSpacing: 0
            Repeater {
                model: row.modelData.kind === "label" ? [] : row.modelData.items
                delegate: ItemTile {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    item: modelData
                    tab: root.tab
                    thumbHeight: root.thumbH
                    renaming: root.renamingPath === modelData.path
                    onActivated: root.activated(modelData)
                    onMenu: (x, y) => { const p = mapToItem(root, x, y); root.itemMenu(modelData, p.x, p.y); }
                    onRenamed: (name) => root.renamed(modelData, name)
                    onRenameCancelled: root.renameCancelled()
                }
            }
            // Keep the last row's tiles the same width as full rows
            Repeater {
                model: row.modelData.kind === "label" ? 0 : Math.max(0, grid.columns - row.modelData.items.length)
                delegate: Item { Layout.fillWidth: true; Layout.preferredWidth: 1; implicitHeight: 1 }
            }
        }
    }
}
