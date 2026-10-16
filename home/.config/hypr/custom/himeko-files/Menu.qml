import QtQuick
import QtQuick.Layouts

// Context menu sheet: an optional row of quick actions on top (iOS style), then a list.
// entries: [{ icon, label, hint, danger, action() } | { separator: true } | { icon, label, sub: [...] }]
Rectangle {
    id: root
    property var quick: []
    property var entries: []
    property int current: -1
    property Item parentMenu: null
    signal done()
    property point origin: Qt.point(0, 0)   // where it pops out from, in the menu's coordinates
    property real pop: 1
    transform: [
        Scale { origin.x: root.origin.x; origin.y: root.origin.y; xScale: root.pop; yScale: root.pop },
        Translate { id: slide }
    ]
    // Top-level menus pop from the pointer; submenus (parentMenu set before completion) slide in 8 px
    Component.onCompleted: {
        if (!Theme.animate) return;
        opacity = 0;
        if (parentMenu) { slide.x = -8; subIn.start(); } else { pop = 0.92; popIn.start(); }
    }
    ParallelAnimation {
        id: popIn
        Anim { target: root; property: "pop"; to: 1; kind: "fastSpatial" }
        Anim { target: root; property: "opacity"; to: 1; kind: "effects" }
    }
    ParallelAnimation {
        id: subIn
        Anim { target: slide; property: "x"; to: 0; kind: "fastSpatial" }
        Anim { target: root; property: "opacity"; to: 1; kind: "effects" }
    }

    width: 300
    height: col.implicitHeight + 16
    radius: 22
    color: Theme.menu
    focus: true
    Sheen { radius: root.radius; light: 0.05; tint: 0.04; edge: 0.12 }

    readonly property var actionable: entries.map((e, i) => e.separator || e.disabled ? -1 : i).filter(i => i >= 0)
    function move(d) {
        const a = actionable;
        if (!a.length) return;
        let at = a.indexOf(current);
        at = at < 0 ? (d > 0 ? 0 : a.length - 1) : (at + d + a.length) % a.length;
        current = a[at];
    }
    function trigger(i) {
        const e = entries[i];
        if (!e || e.disabled) return;
        if (e.sub) { openSub(i); return; }
        root.done();
        e.action();
    }
    Keys.onUpPressed: move(-1)
    Keys.onDownPressed: move(1)
    Keys.onReturnPressed: trigger(current)
    Keys.onEnterPressed: trigger(current)
    Keys.onRightPressed: if (entries[current]?.sub) openSub(current)
    Keys.onLeftPressed: if (parentMenu) { parentMenu.forceActiveFocus(); subLoader.active = false; }
    Keys.onEscapePressed: root.done()

    // ---- submenu ----
    property int subIndex: -1
    property var subEntries: []
    function openSub(i) {
        subIndex = i;
        const s = entries[i].sub;
        if (typeof s === "function") { subEntries = [{ label: "Loading…", disabled: true }]; s(list => subEntries = list); }
        else subEntries = s;
        // By URL (a component can't contain itself); initial properties are set before onCompleted runs
        subLoader.setSource("Menu.qml", { parentMenu: root, width: 250 });
        subLoader.active = true;
    }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
        spacing: 2

        GridLayout {
            visible: root.quick.length > 0
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            columns: Math.max(1, root.quick.length)
            columnSpacing: 6
            Repeater {
                model: root.quick
                delegate: MouseArea {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 60
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.done(); modelData.action(); }
                    Rectangle {
                        anchors.fill: parent
                        radius: 16
                        color: modelData.danger ? Theme.alpha(Theme.error, parent.containsMouse ? 0.22 : 0.14)
                                                : (parent.containsMouse ? Theme.alpha(Theme.text, 0.14) : Theme.alpha(Theme.text, 0.08))
                    }
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2
                        Icon { Layout.alignment: Qt.AlignHCenter; name: modelData.icon; size: 20; color: modelData.danger ? Theme.error : Theme.text }
                        Text { Layout.alignment: Qt.AlignHCenter; text: modelData.label; color: modelData.danger ? Theme.error : Theme.text; font.family: Theme.font; font.pixelSize: 11 }
                    }
                    Accessible.role: Accessible.MenuItem
                    Accessible.name: modelData.label
                }
            }
        }

        Repeater {
            model: root.entries
            delegate: Loader {
                id: entry
                required property var modelData
                required property int index
                Layout.fillWidth: true
                sourceComponent: modelData.separator ? sep : rowComp
                Component {
                    id: sep
                    Item { implicitHeight: 9; Rectangle { anchors.centerIn: parent; width: parent.width - 16; height: 1; color: Theme.edge } }
                }
                Component {
                    id: rowComp
                    MouseArea {
                        implicitHeight: Theme.target
                        hoverEnabled: true
                        cursorShape: entry.modelData.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onEntered: { root.current = entry.index; if (entry.modelData.sub) root.openSub(entry.index); else if (root.subIndex >= 0) { subLoader.active = false; root.subIndex = -1; } }
                        onClicked: root.trigger(entry.index)
                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: root.current === entry.index && !entry.modelData.disabled ? Theme.alpha(Theme.text, 0.10) : "transparent"
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12; anchors.rightMargin: 12
                            spacing: 12
                            Item {
                                implicitWidth: 20; implicitHeight: 20
                                Icon { anchors.centerIn: parent; visible: !entry.modelData.appIcon; name: entry.modelData.icon ?? ""; size: 19; color: entry.modelData.danger ? Theme.error : Theme.text; opacity: entry.modelData.disabled ? 0.5 : 1 }
                                Image { anchors.fill: parent; visible: !!entry.modelData.appIcon; source: entry.modelData.appIcon ?? ""; sourceSize: Qt.size(40, 40); asynchronous: true }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: entry.modelData.label
                                elide: Text.ElideRight
                                color: entry.modelData.danger ? Theme.error : (entry.modelData.disabled ? Theme.outline : Theme.text)
                                font.family: Theme.font; font.pixelSize: 14; font.weight: entry.modelData.bold ? 650 : 450
                            }
                            Text {
                                visible: !!entry.modelData.hint
                                text: entry.modelData.hint ?? ""
                                color: Theme.textDim
                                font.family: Theme.font; font.pixelSize: 12
                            }
                            Icon { visible: !!entry.modelData.sub; name: "chevron_right"; size: 18; color: Theme.textDim }
                        }
                        Accessible.role: Accessible.MenuItem
                        Accessible.name: entry.modelData.label
                    }
                }
            }
        }
    }

    Loader {
        id: subLoader
        active: false
        x: root.width + 8
        y: Math.max(0, 8 + (root.quick.length ? 64 : 0) + root.subIndex * 46 - 8)
        onLoaded: {
            item.entries = Qt.binding(() => root.subEntries);
            item.done.connect(root.done);
        }
    }
}
