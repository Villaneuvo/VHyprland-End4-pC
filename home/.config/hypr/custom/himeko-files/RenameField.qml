import QtQuick

// Inline rename: selects the name without its extension, Enter saves, Esc cancels, clicking away saves.
Rectangle {
    id: root
    property alias text: input.text
    property bool isDir: false
    signal accepted(string name)
    signal cancelled()
    property bool done: false

    implicitHeight: 32
    radius: 10
    color: Theme.surfaceHigh
    border.width: 2
    border.color: Theme.primary

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 10; anchors.rightMargin: 10
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        color: Theme.text
        selectionColor: Theme.primaryContainer
        selectedTextColor: Theme.inkPrimaryContainer
        font.family: Theme.font; font.pixelSize: 13; font.weight: 600
        selectByMouse: true
        Component.onCompleted: {
            forceActiveFocus();
            const dot = root.isDir ? -1 : text.lastIndexOf(".");
            select(0, dot > 0 ? dot : text.length);
        }
        Keys.onReturnPressed: root.finish(true)
        Keys.onEnterPressed: root.finish(true)
        Keys.onEscapePressed: root.finish(false)
        onActiveFocusChanged: if (!activeFocus) root.finish(true)
    }
    function finish(save) {
        if (done) return;
        done = true;
        if (save) accepted(input.text.trim()); else cancelled();
    }
}
