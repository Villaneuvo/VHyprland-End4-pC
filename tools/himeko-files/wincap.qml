// Dev helper: saves one window to a PNG without showing anything (a 1x1 transparent background layer hosts
// the capture). Env: CAP_TITLE (title prefix), CAP_OUT (png path).
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    id: root
    property string title: Quickshell.env("CAP_TITLE")
    property string out: Quickshell.env("CAP_OUT")
    readonly property var target: ToplevelManager.toplevels.values.find(t => t.title.startsWith(root.title)) ?? null
    PanelWindow {
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "wincap"
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: 1
        implicitHeight: 1
        color: "transparent"
        anchors { top: true; left: true }
        ScreencopyView {
            id: view
            // Match the window: a fixed size would letterbox it and grabToImage would squeeze the result
            width: sourceSize.width > 0 ? sourceSize.width : 2000
            height: sourceSize.height > 0 ? sourceSize.height : 1300
            live: true
            captureSource: root.target
            onHasContentChanged: if (hasContent) shot.start()
        }
        Timer {
            id: shot; interval: 600
            onTriggered: view.grabToImage(r => { console.log("SAVED", r.saveToFile(root.out)); Qt.quit() },
                                          Qt.size(view.sourceSize.width, view.sourceSize.height))
        }
        Timer { interval: 8000; running: true; onTriggered: { console.log("TIMEOUT"); Qt.quit() } }
    }
}
