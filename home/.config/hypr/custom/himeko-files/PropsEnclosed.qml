import QtQuick
import QtQuick.Layouts

// Properties › Change Permissions for Enclosed Files: Files and Folders levels per class for everything inside the folder;
// the header's Change applies them (Properties.applyEnclosed), Cancel leaves without changes.
ColumnLayout {
    id: root
    required property Item props
    readonly property var e: props.enclosed
    spacing: 12

    component Level: PropRow {
        property string cls: "files"
        property string who: "u"
        kind: "dropdown"
        key: "enclosed:" + cls + ":" + who
        title: cls === "files" ? "Files" : "Folders"
        value: root.e && root.e[cls] ? root.e[cls][who] : ""
        active: !root.props.enclosedBusy
        onClicked: root.props.openKey(key, null)
    }

    PropGroup { title: "Owner"; Level { who: "u" } Level { who: "u"; cls: "folders" } }
    PropGroup { title: "Group"; Level { who: "g" } Level { who: "g"; cls: "folders" } }
    PropGroup { title: "Others"; Level { who: "o" } Level { who: "o"; cls: "folders" } }
}
