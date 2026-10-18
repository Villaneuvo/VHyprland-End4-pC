import QtQuick
import QtQuick.Layouts
import Quickshell

// Properties › Open With: the apps for this exact type; the default is checked, clicking another makes it the default.
ColumnLayout {
    id: root
    required property Item props
    spacing: 12
    Text {
        visible: root.props.apps.length === 0
        text: "No apps are registered for this type."
        color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13
    }
    PropGroup {
        Repeater {
            model: root.props.apps
            delegate: PropRow {
                required property var modelData
                kind: "choice"
                title: modelData.name
                image: Quickshell.iconPath(modelData.icon, true)
                checked: modelData.isDefault
                onClicked: if (!modelData.isDefault) root.props.setDefault(modelData.id)
            }
        }
    }
}
