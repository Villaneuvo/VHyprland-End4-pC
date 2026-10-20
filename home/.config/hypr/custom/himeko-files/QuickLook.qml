import QtQuick
import QtQuick.Layouts
import QtQuick.Window

// Quick Look (Space): the item large on a glass card over the dimmed folder. Space/Esc close, Left/Right step,
// Enter opens. Bodies by type (Fs.previewType); the heavy ones live in Look*.qml.
FocusScope {
    id: root
    required property var item
    required property var tab
    property Item backdrop
    property bool shown: true           // false while the close fade runs
    signal close()
    signal step(int d)
    signal open()
    signal faded()

    readonly property string kind: Fs.kindOf(item)
    property string mime: ""
    property string appName: ""
    readonly property string type: Fs.previewType(kind, mime)
    readonly property Item body: bodyLoader.item
    property bool bodyFailed: false        // a body couldn't load its file: show the info card instead
    readonly property string shownType: bodyFailed ? "info" : type

    // Answers for an item we've moved past are dropped
    function ask() {
        mime = ""; appName = "";
        const it = item;
        if (it.isDir) return;
        Fs.appsFor(it.path, (apps, m) => {
            if (root.item !== it) return;
            root.mime = m;
            const d = apps.find(a => a.isDefault);
            root.appName = d ? d.name : "";
        });
    }
    onItemChanged: { bodyFailed = false; ask(); bodyFade.restart(); }
    Component.onCompleted: ask()

    property real reveal: shown ? 1 : 0
    Behavior on reveal { Anim { kind: "effects" } }
    onRevealChanged: if (!shown && reveal === 0) faded()
    property real pop: shown ? 1 : 0
    Behavior on pop { enabled: root.shown; Anim { kind: "fastSpatial" } }

    // Everything is ours while open: keys must not reach the folder view (Delete would trash the file)
    Keys.onPressed: (e) => {
        const k = e.key;
        if (k === Qt.Key_Space || k === Qt.Key_Escape) close();
        else if (k === Qt.Key_Left || k === Qt.Key_Up) step(-1);
        else if (k === Qt.Key_Right || k === Qt.Key_Down) step(1);
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) open();
        else if (k === Qt.Key_PageUp && body && body.flip) body.flip(-1);
        else if (k === Qt.Key_PageDown && body && body.flip) body.flip(1);
        else if (k === Qt.Key_M && body && body.muted !== undefined) body.muted = !body.muted;
        e.accepted = true;
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.alpha(Theme.surfaceLowest, 0.45)
        opacity: root.reveal
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: root.close()
        onWheel: (e) => e.accepted = true   // without it the wheel goes through and the folder behind scrolls
    }

    // Card size: pictures and video keep their shape up to 86 % of the window; reading types take a page width
    readonly property real maxW: width * 0.86
    readonly property real maxH: height * 0.86
    readonly property real chromeH: 32 + header.implicitHeight + 12
    readonly property real aspect: body && body.aspect ? body.aspect : 0
    readonly property bool reading: type === "text" || type === "pdf"
    // Small pictures aren't blown up past their own size (the card keeps room for the header)
    readonly property real natural: body && body.naturalWidth ? Math.max(380, body.naturalWidth / Screen.devicePixelRatio) : maxW
    readonly property real bodyW: aspect ? Math.min(maxW - 32, natural, (maxH - chromeH) * aspect)
                                         : reading ? Math.min(760, maxW) - 32
                                         : Math.min(body && body.prefW ? body.prefW : 428, maxW - 32)
    readonly property real bodyH: aspect ? bodyW / aspect : reading ? maxH - chromeH
                                         : Math.min(body && body.prefH ? body.prefH : 380 - chromeH, maxH - chromeH)

    Glass {
        id: card
        backdrop: root.backdrop
        anchors.centerIn: parent
        width: root.bodyW + 32
        height: root.bodyH + root.chromeH
        radius: Theme.rPanel
        tint: Theme.chromeStrong
        opacity: root.reveal
        scale: 0.94 + 0.06 * root.pop
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: (e) => e.accepted = true }   // clicks and the wheel stay on the card

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12
            RowLayout {
                id: header
                Layout.fillWidth: true
                spacing: 12
                Thumb { item: root.item; implicitWidth: 40; implicitHeight: 40; radius: 10; iconSize: 20 }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: root.item.name
                        textFormat: Text.PlainText
                        elide: Text.ElideMiddle
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 15; font.weight: 600
                    }
                    Text {
                        Layout.fillWidth: true
                        text: Fs.labelOf(root.kind, root.item.suffix)
                              + (root.item.isDir ? "" : " · " + Fs.size(root.item.size))
                              + " · " + Fs.date(root.item.modified)
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Theme.textDim
                        font.family: Theme.font; font.pixelSize: 12
                    }
                }
                IconButton {
                    icon: "open_in_new"
                    label: !root.item.isDir && root.appName ? "Open with " + root.appName : "Open"
                    tip: "Enter"
                    Layout.maximumWidth: Math.max(48, root.bodyW * 0.45)
                    onClicked: root.open()
                }
                IconButton { icon: "close"; tip: "Close (Space)"; onClicked: root.close() }
            }
            Item {
                id: bodyArea
                Layout.fillWidth: true
                Layout.fillHeight: true
                NumberAnimation { id: bodyFade; target: bodyArea; property: "opacity"; from: 0; to: 1; duration: Theme.dur("effects") }
                Loader {
                    id: bodyLoader
                    anchors.fill: parent
                    sourceComponent: root.bodyFailed ? infoBody
                                   : root.type === "image" ? imageBody
                                   : root.type === "video" || root.type === "audio" ? mediaBody
                                   : root.type === "pdf" ? pdfBody
                                   : root.type === "text" ? textBody
                                   : root.type === "font" ? fontBody
                                   : root.type === "folder" ? folderBody
                                   : root.type === "" ? null : infoBody
                }
                Connections {
                    target: bodyLoader.item
                    ignoreUnknownSignals: true
                    function onFailed() { root.bodyFailed = true; }
                }
            }
        }
    }

    Component {
        id: imageBody
        Item {
            readonly property real aspect: pic.status === Image.Ready && pic.implicitHeight > 0 ? pic.implicitWidth / pic.implicitHeight : 0
            readonly property real naturalWidth: pic.status === Image.Ready ? pic.implicitWidth : 0
            readonly property bool gif: (root.item.suffix || "").toLowerCase() === "gif"
            readonly property Image pic: gif ? anim : still
            signal failed()              // empty or corrupt picture: the info card says so instead of a blank card
            Image {
                id: still
                anchors.fill: parent
                visible: !parent.gif
                asynchronous: true
                fillMode: Image.PreserveAspectFit
                // Decoded at the largest size the card can take, not at full resolution
                sourceSize: Qt.size(root.maxW * Screen.devicePixelRatio, root.maxH * Screen.devicePixelRatio)
                source: parent.gif ? "" : Fs.uri(root.item.path)
                onStatusChanged: if (status === Image.Error) parent.failed()
            }
            AnimatedImage {
                id: anim
                anchors.fill: parent
                visible: parent.gif
                fillMode: Image.PreserveAspectFit
                source: parent.gif ? Fs.uri(root.item.path) : ""
                onStatusChanged: if (status === Image.Error) parent.failed()
            }
        }
    }

    Component {
        id: mediaBody
        LookMedia { item: root.item; video: root.type === "video" }
    }

    Component {
        id: textBody
        LookText { item: root.item }
    }

    Component {
        id: fontBody
        LookFont { item: root.item }
    }

    Component {
        id: pdfBody
        LookPdf { item: root.item }
    }

    Component {
        id: folderBody
        ColumnLayout {
            spacing: 6
            Item { Layout.fillHeight: true }
            Icon { Layout.alignment: Qt.AlignHCenter; name: "folder"; filled: true; size: 96; color: Theme.inkSecondaryContainer }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: Fs.countLabel(root.tab.countOf(root.item.path))
                color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: 600
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Modified " + Fs.date(root.item.modified)
                color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12
            }
            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: infoBody
        ColumnLayout {
            spacing: 6
            Item { Layout.fillHeight: true }
            Thumb { Layout.alignment: Qt.AlignHCenter; item: root.item; implicitWidth: 160; implicitHeight: 160; iconSize: 64 }
            Repeater {
                model: (root.bodyFailed ? ["Can't preview this " + (root.kind === "pdf" ? "PDF" : "file")] : []).concat([
                        Fs.labelOf(root.kind, root.item.suffix) + " · " + Fs.size(root.item.size),
                        "Modified " + Fs.date(root.item.modified), Fs.displayPath(root.item.path)])
                delegate: Text {
                    required property string modelData
                    required property int index
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: root.bodyW
                    text: modelData
                    textFormat: Text.PlainText
                    elide: Text.ElideMiddle
                    color: index === 0 ? Theme.text : Theme.textDim
                    font.family: Theme.font; font.pixelSize: index === 0 ? 14 : 12
                }
            }
            Item { Layout.fillHeight: true }
        }
    }
}
