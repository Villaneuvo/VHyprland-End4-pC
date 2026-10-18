import QtQuick
import QtQuick.Layouts

// One row of a boxed list, GNOME Files style:
//   property — small dim title above the value (optional icon button at the right)
//   nav      — title … value ›          dropdown — title … value ⌄ (opens a popover)
//   choice   — [icon] title … ✓          switch   — title … toggle          button — centred bold title
Rectangle {
    id: root
    property string kind: "property"
    property string key: ""                // dropdowns: the popover key (Properties.openKey)
    property string title: ""
    property string value: ""
    property string icon: ""               // property rows: icon button at the right
    property string iconTip: ""
    property url image                     // choice rows: leading app icon
    property bool checked: false           // choice: ✓; switch: on
    property bool mixed: false             // switch: knob in the middle
    property bool active: true             // false: read-only look (no chevron, no hover, no clicks)
    property bool selectable: false        // property rows: the value can be selected and copied
    // Use show, not visible: a group hides itself when no row wants to show, and a hidden group makes its rows read as
    // invisible, so it could never come back by looking at visible
    property bool show: true
    visible: show
    readonly property bool clickable: active && kind !== "property"
    readonly property Item anchorItem: trail   // popovers open under this
    signal clicked()
    signal iconClicked()

    Layout.fillWidth: true
    implicitHeight: Math.max(52, body.implicitHeight + 20)
    color: area.containsMouse && clickable ? Theme.alpha(Theme.text, 0.08) : Theme.alpha(Theme.text, 0.05)

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: root.clickable
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    RowLayout {
        id: body
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 12 }
        spacing: 10

        Image {
            visible: root.kind === "choice" && root.image.toString() !== ""
            source: root.image
            sourceSize: Qt.size(28, 28)
            Layout.preferredWidth: 28; Layout.preferredHeight: 28
        }
        ColumnLayout {
            visible: root.kind === "property"
            Layout.fillWidth: true
            spacing: 2
            Text { text: root.title; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
            TextEdit {
                Layout.fillWidth: true
                text: root.value
                readOnly: true
                selectByMouse: root.selectable
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.WrapAnywhere
                color: Theme.text; selectionColor: Theme.primary; selectedTextColor: Theme.inkPrimary
                font.family: Theme.font; font.pixelSize: 14
            }
        }
        Text {
            visible: root.kind !== "property"
            Layout.fillWidth: true
            horizontalAlignment: root.kind === "button" ? Text.AlignHCenter : Text.AlignLeft
            text: root.title
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.kind === "button" && !root.active ? Theme.textDim : Theme.text
            font.family: Theme.font; font.pixelSize: 14; font.weight: root.kind === "button" ? 600 : 450
        }
        Row {
            id: trail
            visible: root.kind === "nav" || root.kind === "dropdown"
            spacing: 4
            Layout.maximumWidth: root.width * 0.62
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, root.width * 0.62 - 24)
                text: root.value
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                color: Theme.textDim; font.family: Theme.font; font.pixelSize: 14
            }
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.active
                name: root.kind === "nav" ? "chevron_right" : "expand_more"
                size: 18
                color: Theme.textDim
            }
        }
        Icon { visible: root.kind === "choice" && root.checked; name: "check"; size: 20; color: Theme.primary }
        Rectangle {
            visible: root.kind === "switch"
            implicitWidth: 44; implicitHeight: 24; radius: 12
            opacity: root.active ? 1 : 0.55
            color: root.checked ? Theme.primary : Theme.alpha(Theme.text, 0.18)
            Rectangle {
                width: 18; height: 18; radius: 9
                anchors.verticalCenter: parent.verticalCenter
                x: root.checked ? parent.width - width - 3 : root.mixed ? (parent.width - width) / 2 : 3
                color: root.checked ? Theme.inkPrimary : Theme.text
                Behavior on x { Anim { kind: "fastSpatial" } }
            }
        }
        IconButton {
            visible: root.kind === "property" && root.icon !== ""
            icon: root.icon; tip: root.iconTip; iconSize: 18
            onClicked: root.iconClicked()
        }
    }
}
