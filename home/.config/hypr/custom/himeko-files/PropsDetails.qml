import QtQuick
import QtQuick.Layouts

// Properties › Details: what the file says about itself (EXIF, tags, PDF info, font names), selectable, never markup.
ColumnLayout {
    id: root
    required property Item props
    spacing: 12
    PropGroup {
        Repeater {
            model: root.props.metaRows
            delegate: PropRow {
                required property var modelData
                title: modelData[0]
                value: modelData[1]
                selectable: true
            }
        }
    }
}
