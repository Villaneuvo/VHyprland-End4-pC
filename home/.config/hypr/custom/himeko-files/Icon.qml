import QtQuick

// A Material Symbols Rounded glyph (same icon font as end4-pC)
Text {
    property string name: ""
    property real size: 20
    property bool filled: false
    text: name
    font.family: Theme.iconFont
    font.pixelSize: size
    font.variableAxes: ({ "FILL": filled ? 1 : 0, "wght": 450, "opsz": Math.max(20, Math.min(48, size)) })
    color: Theme.text
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    renderType: Text.NativeRendering
}
