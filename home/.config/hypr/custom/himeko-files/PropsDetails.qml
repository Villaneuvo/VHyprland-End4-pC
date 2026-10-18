import QtQuick
import QtQuick.Layouts

// Properties › Details: what the file says about itself (EXIF, tags, PDF info, font names), selectable, never markup.
GridLayout {
    id: root
    required property Item props
    columns: 2
    columnSpacing: 14
    rowSpacing: 6
    Repeater {
        model: root.props.metaRows
        delegate: Text {
            required property var modelData
            Layout.row: index
            Layout.column: 0
            Layout.alignment: Qt.AlignTop | Qt.AlignRight
            required property int index
            text: modelData[0]
            color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13
        }
    }
    Repeater {
        model: root.props.metaRows
        delegate: TextEdit {
            required property var modelData
            required property int index
            Layout.row: index
            Layout.column: 1
            Layout.fillWidth: true
            readOnly: true
            selectByMouse: true
            textFormat: TextEdit.PlainText
            wrapMode: TextEdit.WrapAnywhere
            text: modelData[1]
            color: Theme.text; selectionColor: Theme.primary; selectedTextColor: Theme.inkPrimary
            font.family: Theme.font; font.pixelSize: 13
        }
    }
}
