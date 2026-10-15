import QtQuick

// The glass finish over a translucent surface (the design canvas's look): a soft light from the top that fades
// out, a faint accent cast from the left, and a hairline edge. Put it under the surface's content.
Item {
    id: root
    property real radius: 0
    property real light: 0.07      // top highlight strength
    property real tint: 0.06       // accent cast strength
    property real edge: 0.10       // hairline strength
    anchors.fill: parent

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, root.light) }
            GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, root.light * 0.9) }
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Theme.alpha(Theme.primary, root.tint) }
            GradientStop { position: 0.6; color: Theme.alpha(Theme.primary, 0) }
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, root.edge)
    }
}
