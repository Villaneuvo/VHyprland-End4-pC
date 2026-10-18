import QtQuick
import QtQuick.Layouts

// Quick Look body for text and code: the first 256 KB (ops.sh text) in the mono font with line numbers, never as
// markup. Binary content (a NUL byte) fails over to the info card.
Item {
    id: root
    required property var item
    property string content: ""
    signal failed()

    function load() {
        content = "";
        const it = item;
        Fs.run([Fs.ops, "text", it.path], (text, code) => {
            if (root.item !== it) return;
            if (code !== 0) return root.failed();
            root.content = text.endsWith("\n") ? text.slice(0, -1) : text;
        });
    }
    onItemChanged: load()
    Component.onCompleted: load()

    ColumnLayout {
        anchors.fill: parent
        spacing: 6
        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: lines.width
            contentHeight: lines.height
            Row {
                id: lines
                spacing: 14
                Text {
                    text: Array.from({ length: root.content ? root.content.split("\n").length : 0 }, (_, i) => i + 1).join("\n")
                    horizontalAlignment: Text.AlignRight
                    color: Theme.outline
                    font.family: Theme.mono; font.pixelSize: 13
                }
                Text {
                    text: root.content
                    textFormat: Text.PlainText
                    color: Theme.text
                    font.family: Theme.mono; font.pixelSize: 13
                }
            }
        }
        Text {
            visible: root.item.size > 262144
            text: "Showing the first 256 KB"
            color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12
        }
    }
}
