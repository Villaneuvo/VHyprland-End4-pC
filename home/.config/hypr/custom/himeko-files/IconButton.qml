import QtQuick

// Round (or pill, with a label) button. 44 px target by default.
MouseArea {
    id: root
    property string icon: ""
    property string label: ""
    property string tip: ""
    property bool active: false
    property bool enabledLook: true
    property color fg: active ? Theme.inkPrimary : (enabledLook ? Theme.text : Theme.outline)
    property color bg: active ? Theme.primary : (containsMouse ? Theme.hover : "transparent")
    property real iconSize: 20
    property int radius: height / 2
    implicitHeight: Theme.target
    implicitWidth: label ? row.implicitWidth + 32 : implicitHeight
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.pressed ? Theme.pressed : root.bg
        Behavior on color { ColorAnimation { duration: 120 } }
    }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 8
        Icon { name: root.icon; size: root.iconSize; color: root.fg; visible: root.icon !== ""; anchors.verticalCenter: parent.verticalCenter }
        Text {
            visible: root.label !== ""
            text: root.label
            color: root.fg
            font.family: Theme.font; font.pixelSize: 13; font.weight: root.active ? 650 : 500
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    Accessible.role: Accessible.Button
    Accessible.name: tip || label || icon
}
