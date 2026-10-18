import QtQuick
import QtQuick.Layouts
import Quickshell

// Properties › Open With: the apps registered for the file's type; "Set as default" changes that exact type.
ColumnLayout {
    id: root
    required property Item props
    spacing: 4

    Text {
        visible: root.props.apps.length === 0
        text: "No apps are registered for this type."
        color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13
    }
    Repeater {
        model: root.props.apps
        delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 10
            Image {
                source: Quickshell.iconPath(modelData.icon, true)
                sourceSize: Qt.size(28, 28)
                Layout.preferredWidth: 28; Layout.preferredHeight: 28
            }
            Text {
                Layout.fillWidth: true
                text: modelData.name
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: modelData.isDefault ? 600 : 450
            }
            Rectangle {
                visible: modelData.isDefault
                implicitWidth: badge.implicitWidth + 18; implicitHeight: 24; radius: 12
                color: Theme.secondaryContainer
                Text { id: badge; anchors.centerIn: parent; text: "Default"; color: Theme.inkSecondaryContainer; font.family: Theme.font; font.pixelSize: 12 }
            }
            IconButton {
                visible: !modelData.isDefault
                icon: "check_circle"; label: "Set as default"; iconSize: 16
                onClicked: root.props.setDefault(modelData.id)
            }
        }
    }
}
