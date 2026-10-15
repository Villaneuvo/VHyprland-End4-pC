import QtQuick
import QtQuick.Layouts

// Information panel (F11): preview, chips, metadata and the actions that matter for the selection.
Rectangle {
    id: root
    required property var tab
    readonly property var item: tab.selectedCount === 1 ? tab.selectedItems[0] : null
    readonly property string kind: item ? Fs.kindOf(item) : "folder"
    property var details: ({})
    signal openItem(var item)

    implicitWidth: 320
    radius: Theme.rPanel
    color: Theme.chrome
    border.width: 1
    border.color: Theme.edge

    onItemChanged: {
        details = {};
        const it = item;
        if (it) Fs.details(it, (d) => { if (root.item && root.item.path === it.path) root.details = d; });
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 14

        Item {
            Layout.fillWidth: true
            implicitHeight: 180
            Thumb {
                anchors.fill: parent
                visible: root.item !== null
                item: root.item ?? { name: "", path: "", isDir: true, suffix: "" }
                radius: 12
                iconSize: 64
            }
            ColumnLayout {
                visible: root.item === null
                anchors.centerIn: parent
                spacing: 8
                Item {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 72; implicitHeight: 72
                    Shape { anchors.fill: parent; kind: root.tab.selectedCount > 1 ? "burst" : "flower"; color: Theme.secondaryContainer }
                    Text {
                        anchors.centerIn: parent
                        visible: root.tab.selectedCount > 1
                        text: root.tab.selectedCount
                        color: Theme.inkSecondaryContainer; font.family: Theme.font; font.pixelSize: 22; font.weight: 700
                    }
                    Icon { anchors.centerIn: parent; visible: root.tab.selectedCount <= 1; name: "folder_open"; size: 32; filled: true; color: Theme.inkSecondaryContainer }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4; Layout.rightMargin: 4
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: root.item ? root.item.name : (root.tab.selectedCount > 1 ? root.tab.selectedCount + " items selected" : root.tab.name)
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 3
                elide: Text.ElideRight
                color: Theme.text; font.family: Theme.font; font.pixelSize: 18; font.weight: 650
            }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: {
                        if (!root.item) return root.tab.selectedCount > 1 ? [Fs.size(root.tab.selectedSize)] : [root.tab.items.length + " items"];
                        const c = [Fs.labelOf(root.kind, root.item.suffix)];
                        if (root.details.extra) c.push(root.item.isDir ? root.details.extra + " items" : root.details.extra);
                        if (!root.item.isDir) c.push(Fs.size(root.item.size));
                        return c;
                    }
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        implicitWidth: chip.implicitWidth + 20; implicitHeight: 26; radius: 13
                        color: index === 0 ? Theme.secondaryContainer : Theme.alpha(Theme.text, 0.10)
                        Text { id: chip; anchors.centerIn: parent; text: modelData; color: index === 0 ? Theme.inkSecondaryContainer : Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                    }
                }
            }
        }

        GridLayout {
            visible: root.item !== null
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 12; rowSpacing: 10
            Rectangle { Layout.columnSpan: 2; Layout.fillWidth: true; implicitHeight: 1; color: "transparent" }
            Meta { label: "Modified" }
            MetaValue { text: root.item ? Fs.date(root.item.modified) : "" }
            Meta { label: "Created"; visible: !!root.details.created }
            MetaValue { text: root.details.created ?? ""; visible: !!root.details.created }
            Meta { label: "Location" }
            MetaValue { text: root.tab.path.replace(Fs.home, "~") }
        }

        Item { Layout.fillHeight: true }

        ColumnLayout {
            visible: root.item !== null
            Layout.fillWidth: true
            spacing: 8
            IconButton {
                visible: root.kind === "image"
                Layout.fillWidth: true
                implicitHeight: 48
                icon: "wallpaper"; label: "Set as wallpaper"; active: true
                onClicked: Fs.setWallpaper(root.item.path)
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                IconButton {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    label: root.item && root.item.isDir ? "Open" : "Open"
                    icon: "open_in_new"
                    bg: Theme.secondaryContainer; fg: Theme.inkSecondaryContainer
                    onClicked: root.openItem(root.item)
                }
                IconButton {
                    implicitWidth: 48; implicitHeight: 48
                    icon: "folder_managed"; tip: "Open in Dolphin"
                    bg: containsMouse ? Theme.hover : "transparent"
                    onClicked: Fs.openDolphin(root.item.isDir ? root.item.path : root.tab.path)
                }
            }
        }
    }

    component Meta: Text {
        property string label
        text: label
        color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13
        Layout.preferredWidth: 80
    }
    component MetaValue: Text {
        Layout.fillWidth: true
        elide: Text.ElideMiddle
        color: Theme.text; font.family: Theme.font; font.pixelSize: 13
    }
}
