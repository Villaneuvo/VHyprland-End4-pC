import QtQuick
import QtQuick.Layouts

// Properties › Permissions: owner/group, access per class as Nautilus words it, and "allow executing" for files.
// Choices apply at once (Properties.setPerm); read-only when you don't own every item or it's a link.
ColumnLayout {
    id: root
    required property Item props
    readonly property var fi: props.firstInfo
    readonly property bool editable: props.permsEditable
    spacing: 10

    GridLayout {
        columns: 2
        columnSpacing: 14
        rowSpacing: 6
        visible: root.fi !== null
        Text { text: "Owned by"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13 }
        Text {
            text: !root.fi ? "" : root.props.info.every(i => i && i.owner === root.fi.owner) ? (root.fi.mine ? "You (" + root.fi.owner + ")" : root.fi.owner) : "Mixed"
            textFormat: Text.PlainText; color: Theme.text; font.family: Theme.font; font.pixelSize: 13
        }
        Text { text: "Group"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13 }
        Text {
            text: !root.fi ? "" : root.props.info.every(i => i && i.group === root.fi.group) ? root.fi.group : "Mixed"
            textFormat: Text.PlainText; color: Theme.text; font.family: Theme.font; font.pixelSize: 13
        }
    }

    Repeater {
        // One block per class present: files and folders get their own rows when both are selected
        model: root.props.mixedKinds ? [{ cls: "files", isDir: false }, { cls: "folders", isDir: true }]
                                     : [{ cls: "", isDir: root.props.first.isDir }]
        delegate: ColumnLayout {
            id: blockCol
            required property var modelData
            readonly property var state: modelData.cls ? root.props.permsState[modelData.cls] : root.props.permsState
            Layout.fillWidth: true
            spacing: 6
            Text {
                visible: modelData.cls !== ""
                text: modelData.isDir ? "Folders" : "Files"
                color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: 600
            }
            Repeater {
                model: [["u", "Owner"], ["g", "Group"], ["o", "Others"]]
                delegate: RowLayout {
                    id: classRow
                    required property var modelData
                    readonly property string value: blockCol.state ? blockCol.state[modelData[0]] ?? "" : ""
                    Layout.fillWidth: true
                    spacing: 6
                    Text {
                        Layout.preferredWidth: 56
                        text: modelData[1]
                        color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        Repeater {
                            model: Fs.levels(blockCol.modelData.isDir)
                            delegate: Rectangle {
                                required property string modelData
                                readonly property bool on: modelData === classRow.value
                                implicitWidth: lvl.implicitWidth + 20; implicitHeight: 28; radius: 14
                                opacity: root.editable ? 1 : 0.55
                                color: on ? Theme.secondaryContainer : area.containsMouse && root.editable ? Theme.hover : "transparent"
                                border.width: on ? 0 : 1
                                border.color: Theme.alpha(Theme.text, 0.12)
                                Text {
                                    id: lvl
                                    anchors.centerIn: parent
                                    text: parent.modelData
                                    color: parent.on ? Theme.inkSecondaryContainer : Theme.text
                                    font.family: Theme.font; font.pixelSize: 12
                                }
                                MouseArea {
                                    id: area
                                    anchors.fill: parent
                                    enabled: root.editable
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.props.setPerm(blockCol.modelData.cls, classRow.modelData[0], parent.modelData)
                                }
                            }
                        }
                        Text {
                            visible: classRow.value === "Mixed" || classRow.value === "Custom"
                            text: classRow.value
                            color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12
                            height: 28; verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
            // Files: the executable bit
            RowLayout {
                visible: !blockCol.modelData.isDir
                spacing: 10
                Rectangle {
                    readonly property string exec: root.props.execState
                    implicitWidth: 40; implicitHeight: 22; radius: 11
                    opacity: root.editable ? 1 : 0.55
                    color: exec === "on" ? Theme.primary : Theme.alpha(Theme.text, 0.18)
                    Rectangle {
                        width: 16; height: 16; radius: 8
                        anchors.verticalCenter: parent.verticalCenter
                        x: parent.exec === "on" ? parent.width - width - 3 : parent.exec === "Mixed" ? (parent.width - width) / 2 : 3
                        color: parent.exec === "on" ? Theme.inkPrimary : Theme.text
                        Behavior on x { Anim { kind: "fastSpatial" } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: root.editable
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.props.setPerm(blockCol.modelData.cls, "exec", parent.exec === "on" ? "off" : "on")
                    }
                }
                Text { text: "Allow executing file as program"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
            }
        }
    }

    Text {
        visible: !root.editable && root.props.info.length > 0
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: root.props.info.some(i => i && i.type === "link") ? "Permissions of a link can't be changed; change the file it points to."
                                                               : "Only the owner can change these permissions."
        color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12
    }
}
