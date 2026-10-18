import QtQuick
import QtQuick.Layouts

// Properties › Permissions, as GNOME Files lays it out: Owner, Group, Other Users, each with its Access dropdown (Files
// and Folders rows when both are selected), the executable switch for files and the enclosed-files button for a folder.
// Read-only rows (no chevron) when you don't own every item or it's a link.
ColumnLayout {
    id: root
    required property Item props
    readonly property var st: props.permsState
    readonly property bool editable: props.permsEditable
    readonly property bool mixed: props.mixedKinds
    readonly property var fi: props.firstInfo
    function lvl(cls, who) { return !st ? "" : cls ? (st[cls] ? st[cls][who] : "") : st[who] ?? ""; }
    spacing: 12

    component Access: PropRow {
        property string cls: ""
        property string who: "u"
        kind: "dropdown"
        key: "access:" + (cls ? cls + ":" : "") + who
        title: cls === "files" ? "Files" : cls === "folders" ? "Folders" : "Access"
        value: root.lvl(cls, who)
        active: root.editable
        show: cls === "" ? !root.mixed : root.mixed
        onClicked: root.props.openKey(key, null)
    }

    PropGroup {
        PropRow {
            kind: "dropdown"; active: false
            title: "Owner"
            value: !root.fi ? "" : root.props.info.every(i => i && i.owner === root.fi.owner) ? root.fi.owner + (root.fi.mine ? " (You)" : "") : "Mixed"
        }
        Access { who: "u" }
        Access { who: "u"; cls: "files" }
        Access { who: "u"; cls: "folders" }
    }
    PropGroup {
        PropRow {
            kind: "dropdown"; key: "group"
            title: "Group"
            value: root.props.groupState
            active: root.props.canGroup && root.props.groups.length > 0
            onClicked: root.props.openKey(key, null)
        }
        Access { who: "g" }
        Access { who: "g"; cls: "files" }
        Access { who: "g"; cls: "folders" }
    }
    PropGroup {
        title: "Other Users"
        Access { who: "o" }
        Access { who: "o"; cls: "files" }
        Access { who: "o"; cls: "folders" }
    }
    PropGroup {
        PropRow {
            kind: "switch"
            show: root.props.items.some(it => !it.isDir)
            title: "Allow Executing File as Program"
            checked: root.props.execState === "on"
            mixed: root.props.execState === "Mixed"
            active: root.editable
            onClicked: root.props.setPerm(root.mixed ? "files" : "", "exec", root.props.execState === "on" ? "off" : "on")
        }
    }
    PropGroup {
        PropRow {
            kind: "button"
            show: root.props.one && root.props.first.isDir && root.editable
            title: "Change Permissions for Enclosed Files…"
            onClicked: root.props.goPage("Enclosed")
        }
    }
    Text {
        visible: !root.editable && root.props.info.length > 0
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: root.props.info.some(i => i && i.type === "link") ? "Permissions of a link can't be changed; change the file it points to."
                                                               : "Only the owner can change these permissions."
        color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12
    }
}
