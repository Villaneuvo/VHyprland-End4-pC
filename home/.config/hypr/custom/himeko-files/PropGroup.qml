import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

// A boxed list: rows in one rounded group with 2 px gaps, an optional bold section title above. Hidden when no row is.
ColumnLayout {
    id: root
    property string title: ""
    default property alias rows: list.data
    Layout.fillWidth: true
    spacing: 6
    visible: list.children.some(c => c.show === true)

    Text {
        visible: root.title !== ""
        Layout.leftMargin: 2
        text: root.title
        color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: 600
    }
    Item {
        id: box
        Layout.fillWidth: true
        implicitHeight: list.implicitHeight
        ColumnLayout { id: list; width: parent.width; spacing: 2 }
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: mask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
    }
    Rectangle { id: mask; width: box.width; height: box.height; radius: 14; visible: false; layer.enabled: true }
}
