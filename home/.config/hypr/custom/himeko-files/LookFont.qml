import QtQuick
import QtQuick.Layouts

// Quick Look body for fonts: the family name and a pangram at four sizes, drawn with the file itself.
Item {
    id: root
    required property var item
    signal failed()
    readonly property real prefW: 640
    readonly property real prefH: 420
    // Families ship as several files (Regular, Bold, Italic…): draw the style this file holds, not the family default
    property string style: ""
    Component.onCompleted: { const it = item; Fs.run([Fs.ops, "fontstyle", it.path], (t) => { if (root.item === it) root.style = t.trim(); }); }

    FontLoader {
        id: face
        source: Fs.uri(root.item.path)
        onStatusChanged: if (status === FontLoader.Error) root.failed()
    }
    ColumnLayout {
        anchors.fill: parent
        visible: face.status === FontLoader.Ready
        spacing: 10
        clip: true
        Text {
            Layout.fillWidth: true
            text: face.name + (root.style ? " " + root.style : "")
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.text; font.family: face.name; font.styleName: root.style; font.pixelSize: 28
        }
        Repeater {
            model: [14, 20, 32, 48]
            delegate: Text {
                required property int modelData
                Layout.fillWidth: true
                text: "The quick brown fox jumps over the lazy dog"
                elide: Text.ElideRight
                color: Theme.text; font.family: face.name; font.styleName: root.style; font.pixelSize: modelData
            }
        }
        Text {
            Layout.fillWidth: true
            text: "ABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz\n0123456789"
            color: Theme.textDim; font.family: face.name; font.styleName: root.style; font.pixelSize: 16
        }
        Item { Layout.fillHeight: true }
    }
}
