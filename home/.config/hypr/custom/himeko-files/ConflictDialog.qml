import QtQuick
import QtQuick.Layouts

// A name is taken (transfer.py asks): GNOME Files' "Replace file?" / "Merge folder?" in glass. `req` is the ask;
// `answered(a)` gives back {choice, all} or {cancel: true}. Modal: it takes every key; Enter keeps both (never loses
// anything), Esc cancels the whole job.
FocusScope {
    id: root
    required property var req
    property Item backdrop
    signal answered(var a)
    property bool all: false

    readonly property bool folder: req.isDir
    readonly property string destName: Fs.baseName(req.dest)   // a server's top folder shows as its name
    function choose(choice) { answered({ choice: choice, all: all }); }
    function cancel() { answered({ cancel: true }); }
    // Test hook (Browser IPC)
    function state() {
        return { title: title.text, message: message.text, more: req.more, buttons: [skipBtn.label, keepBtn.label, destroyBtn.label] };
    }

    Keys.onPressed: (e) => {
        if (e.key === Qt.Key_Escape) cancel();
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) choose("keep");
        e.accepted = true;
    }
    Component.onCompleted: forceActiveFocus()

    Rectangle { anchors.fill: parent; color: Theme.alpha(Theme.surfaceLowest, 0.45) }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: (e) => e.accepted = true }

    Glass {
        backdrop: root.backdrop
        anchors.centerIn: parent
        width: Math.min(460, root.width * 0.92)
        height: col.implicitHeight + 40
        radius: Theme.rPanel
        tint: Theme.alpha(Theme.surfaceMid, 0.94)
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            spacing: 14
            Icon { Layout.alignment: Qt.AlignHCenter; name: root.folder ? "folder_copy" : "file_copy"; size: 34; color: Theme.primary }
            Text {
                id: title
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.folder ? "Merge Folder “" + root.req.name + "”?" : "Replace “" + root.req.name + "”?"
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: 650
            }
            Text {
                id: message
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: (root.folder ? "A folder with the same name already exists in “" + root.destName + "”. Merging asks before replacing any files in it."
                                   : "A file with the same name already exists in “" + root.destName + "”.")
                      + (!root.folder && !root.req.canTrash ? "\nThere's no Trash here: the existing file will be overwritten." : "")
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13
            }

            PropGroup {
                Side { title: "Original"; info: root.req.old; other: root.req.new }
                Side { title: "Replacement"; info: root.req.new; other: root.req.old }
                PropRow {
                    kind: "switch"; title: "Apply to All"; checked: root.all
                    show: root.req.more
                    visible: show
                    onClicked: root.all = !root.all
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8
                IconButton { label: "Cancel"; bg: containsMouse ? Theme.hover : "transparent"; onClicked: root.cancel() }
                Item { Layout.fillWidth: true }
                IconButton { id: skipBtn; label: "Skip"; bg: containsMouse ? Theme.hover : Theme.alpha(Theme.text, 0.08); onClicked: root.choose("skip") }
                IconButton { id: keepBtn; label: "Keep Both"; active: true; onClicked: root.choose("keep") }
                IconButton {
                    id: destroyBtn
                    label: root.folder ? "Merge" : "Replace"
                    fg: Theme.error
                    bg: Theme.alpha(Theme.error, containsMouse ? 0.22 : 0.14)
                    onClicked: root.choose(root.folder ? "merge" : "replace")
                }
            }
        }
    }

    // One side of the comparison: icon, "size · modified", and a dim "newer"/"larger" tag on the side that is
    component Side: Rectangle {
        id: side
        property string title
        property var info
        property var other
        property bool show: true
        readonly property bool newer: info.mtime > other.mtime
        readonly property bool larger: !root.folder && info.size > other.size
        Layout.fillWidth: true
        implicitHeight: 60
        color: Theme.alpha(Theme.text, 0.05)
        RowLayout {
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 14 }
            spacing: 12
            Icon { name: root.folder ? "folder" : Fs.iconOf(Fs.kindOf({ isDir: false, suffix: root.req.name.includes(".") ? root.req.name.slice(root.req.name.lastIndexOf(".") + 1) : "" })); size: 22; color: Theme.textDim }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text { text: side.title; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12 }
                Text {
                    Layout.fillWidth: true
                    text: (root.folder ? "Folder" : Fs.size(side.info.size)) + " · " + Fs.date(new Date(side.info.mtime * 1000))
                    elide: Text.ElideRight
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 14
                }
            }
            Text {
                visible: text !== ""
                text: [side.newer ? "newer" : "", side.larger ? "larger" : ""].filter(t => t).join(" · ")
                color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12
            }
        }
    }
}
