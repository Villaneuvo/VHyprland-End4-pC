import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell

// Quick Look body for PDFs: one page at a time, rendered by poppler in the sandbox (ops.sh page) into a tmpfs cache.
// Page Up/Down, the wheel or the arrows flip pages.
Item {
    id: root
    required property var item
    property int page: 1
    property int pages: 0
    property string shown: ""              // rendered PNG of the current page; the previous one stays until it's ready
    signal failed()
    readonly property string cache: Quickshell.env("XDG_RUNTIME_DIR") + "/himeko-files/pages"

    function flip(d) { if (pages) page = Math.max(1, Math.min(pages, page + d)); }
    // Answers for another item or page than the one now shown are dropped
    function load() {
        pages = 0; page = 1; shown = "";
        const it = item;
        Fs.run([Fs.ops, "pages", it.path], (text, code) => {
            if (root.item !== it) return;
            if (code !== 0) return root.failed();
            root.pages = parseInt(text);
            root.render();
        });
    }
    function render() {
        if (!pages) return;
        const it = item, n = page;
        // Rendered at the card's width in 200 px steps, so a small resize reuses the cached page
        const w = Math.ceil(Math.max(600, pageArea.width * Screen.devicePixelRatio) / 200) * 200;
        const out = cache + "/" + Qt.md5(it.path + it.modified) + "-" + n + "-" + w + ".png";
        Fs.run([Fs.ops, "page", it.path, String(n), String(w), out], (t, code) => {
            if (root.item === it && root.page === n && code === 0) root.shown = out;
        });
    }
    onItemChanged: load()
    onPageChanged: render()
    Component.onCompleted: load()

    ColumnLayout {
        anchors.fill: parent
        spacing: 8
        Item {
            id: pageArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            Image {
                anchors.fill: parent
                asynchronous: true
                cache: false
                fillMode: Image.PreserveAspectFit
                source: root.shown ? "file://" + root.shown : ""
            }
            MouseArea {
                anchors.fill: parent
                onWheel: (e) => root.flip(e.angleDelta.y < 0 ? 1 : -1)
            }
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 8
            IconButton { icon: "chevron_left"; tip: "Previous page (Page Up)"; enabledLook: root.page > 1; onClicked: root.flip(-1) }
            Text {
                text: root.pages ? "Page " + root.page + " of " + root.pages : "Loading…"
                color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12; font.features: { "tnum": 1 }
            }
            IconButton { icon: "chevron_right"; tip: "Next page (Page Down)"; enabledLook: root.page < root.pages; onClicked: root.flip(1) }
        }
    }
}
