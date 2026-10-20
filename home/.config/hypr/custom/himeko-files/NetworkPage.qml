import QtQuick
import QtQuick.Layouts

// The Network page, like Nautilus 50's: Connected, Previous, Available on Current Network. On "network:<address>"
// (a computer) it lists that computer's shares instead. The address bar lives in Browser, under the glass.
Flickable {
    id: root
    required property var tab
    required property Item browser
    readonly property string computer: tab.path.length > 8 ? tab.path.slice(8) : ""   // "network:" + address
    property var previous: []           // addresses, newest first
    property var found: []              // [{ name, target, kind }]
    property bool looking: false
    property var finder: null

    function refresh() {
        Fs.serversList((list) => root.previous = list);
        if (finder) finder.running = false;
        found = [];
        looking = true;
        const asked = computer;
        finder = Fs.browse(asked || "network:///",
            (it) => { if (root.computer === asked) root.found = root.found.concat([it]); },
            (err) => { if (root.computer !== asked) return; root.looking = false; if (err) Fs.failed(err); });
    }
    Component.onCompleted: refresh()
    onComputerChanged: refresh()
    Component.onDestruction: if (finder) finder.running = false

    // Previous servers that aren't connected now (a connected server's folders count as connected)
    readonly property var previousShown: previous.filter(a => !Fs.netMounts.some(m => Fs.normAddress(a).startsWith(m.uri.replace(/\/$/, ""))))
    // Test hook (Browser IPC): what the page lists
    function rows() {
        const found = root.found.map(f => ({ section: "Available", name: f.name, address: f.target }));
        if (computer) return found;
        return Fs.netMounts.map(m => ({ section: "Connected", name: m.name, address: m.uri }))
            .concat(previousShown.map(a => ({ section: "Previous", name: Fs.netPinName(a, ""), address: a })))
            .concat(found);
    }
    function removePrevious(a) { Fs.serverRemove(a); previous = previous.filter(x => x !== a); }
    function menuAt(item, entries) { const p = item.mapToItem(browser, item.width - 40, item.height / 2); browser.showMenu(p.x, p.y, [], entries); }

    contentHeight: col.implicitHeight + 160
    topMargin: 134
    boundsBehavior: Flickable.StopAtBounds
    clip: false

    ColumnLayout {
        id: col
        x: 28
        width: root.width - 52
        spacing: 22

        ColumnLayout {
            spacing: 2
            Text {
                text: root.tab.name
                textFormat: Text.PlainText   // a computer's name comes from the network
                color: Theme.text; font.family: Theme.font; font.pixelSize: 34; font.weight: 700; font.letterSpacing: -0.4
            }
            Text {
                text: root.computer ? "Shared folders" : Fs.netMounts.length + " connected · " + root.previousShown.length + " previous"
                color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13
            }
        }

        PropGroup {
            title: "Connected"
            visible: !root.computer && Fs.netMounts.length > 0
            Repeater {
                model: Fs.netMounts
                delegate: NetRow {
                    id: mountRow
                    required property var modelData
                    icon: Fs.netIcon(modelData.uri); title: modelData.name; subtitle: modelData.uri
                    trailingIcon: modelData.canUnmount ? "eject" : ""; trailingTip: "Unmount"
                    onTrailingClicked: Fs.unmount(modelData.uri, false)
                    onClicked: root.tab.go(modelData.path)
                    onMenu: root.menuAt(mountRow, [
                        { icon: "folder_open", label: "Open", action: () => root.tab.go(modelData.path) },
                        { icon: "tab", label: "Open in New Tab", action: () => root.browser.newTab(modelData.path, false) },
                        { icon: "link", label: "Copy Address", action: () => Fs.copyText(modelData.uri) },
                        { separator: true },
                        { icon: "eject", label: "Unmount", action: () => Fs.unmount(modelData.uri, false) }
                    ])
                }
            }
        }

        PropGroup {
            title: "Previous"
            visible: !root.computer && root.previousShown.length > 0
            Repeater {
                model: root.previousShown
                delegate: NetRow {
                    id: prevRow
                    required property string modelData
                    icon: Fs.netIcon(modelData); title: Fs.netPinName(modelData, ""); subtitle: modelData
                    onClicked: root.browser.openAddress(modelData, true)
                    onMenu: root.menuAt(prevRow, [
                        { icon: "link", label: "Connect", action: () => root.browser.openAddress(modelData, true) },
                        { icon: "content_copy", label: "Copy Address", action: () => Fs.copyText(modelData) },
                        { separator: true },
                        { icon: "close", label: "Remove", action: () => root.removePrevious(modelData) }
                    ])
                }
            }
        }

        PropGroup {
            title: root.computer ? "" : "Available on Current Network"
            Repeater {
                model: root.found
                delegate: NetRow {
                    required property var modelData
                    icon: modelData.kind === "computer" ? "computer" : Fs.netIcon(modelData.target); title: modelData.name; subtitle: modelData.target
                    onClicked: modelData.kind === "computer" ? root.tab.go("network:" + modelData.target) : root.browser.openAddress(modelData.target)
                }
            }
            NetRow {
                show: root.found.length === 0
                icon: root.looking ? "radar" : "wifi_off"
                title: root.looking ? "Looking for computers…" : "Nothing found on this network"
                dim: true
            }
        }
    }

    // One row: icon, name, the address dimmed below, an optional button at the right (eject)
    component NetRow: Rectangle {
        id: row
        property string icon
        property string title
        property string subtitle
        property string trailingIcon: ""
        property string trailingTip: ""
        property bool dim: false
        property bool show: true            // PropGroup hides itself when no row shows
        visible: show
        signal clicked()
        signal trailingClicked()
        signal menu()
        Layout.fillWidth: true
        implicitHeight: 60
        radius: 4
        color: area.containsMouse && !dim ? Theme.alpha(Theme.text, 0.08) : Theme.alpha(Theme.text, 0.05)
        MouseArea {
            id: area
            anchors.fill: parent
            enabled: !row.dim
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: (m) => m.button === Qt.RightButton ? row.menu() : row.clicked()
        }
        RowLayout {
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 8 }
            spacing: 12
            Rectangle {
                implicitWidth: 36; implicitHeight: 36; radius: 12
                color: row.dim ? "transparent" : Theme.secondaryContainer
                Icon { anchors.centerIn: parent; name: row.icon; size: 20; color: row.dim ? Theme.textDim : Theme.inkSecondaryContainer }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: row.title
                    textFormat: Text.PlainText   // server-provided names
                    elide: Text.ElideRight
                    color: row.dim ? Theme.textDim : Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: 550
                }
                Text {
                    visible: row.subtitle !== ""
                    Layout.fillWidth: true
                    text: row.subtitle
                    textFormat: Text.PlainText
                    elide: Text.ElideMiddle
                    color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12
                }
            }
            IconButton {
                visible: row.trailingIcon !== ""
                icon: row.trailingIcon; tip: row.trailingTip; iconSize: 18
                implicitWidth: 40; implicitHeight: 40
                onClicked: row.trailingClicked()
            }
        }
    }
}
