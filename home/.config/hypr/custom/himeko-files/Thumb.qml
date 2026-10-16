import QtQuick
import QtQuick.Effects

// Preview of an item: a thumbnail for images/videos (shared freedesktop cache), else a kind icon on a tonal tile.
Item {
    id: root
    required property var item
    property real radius: Theme.rThumb
    property real iconSize: Math.min(width, height) * 0.36
    readonly property string kind: Fs.kindOf(item)
    readonly property bool previewable: kind === "image" || kind === "video"
    property bool ready: false

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: !img.visible
        color: root.kind === "folder" ? Theme.secondaryContainer
             : root.kind === "image" || root.kind === "video" ? Theme.primaryContainer
             : root.kind === "archive" || root.kind === "app" ? Theme.tertiaryContainer
             : Theme.surfaceHighest
        Icon {
            anchors.centerIn: parent
            name: Fs.iconOf(root.kind)
            size: root.iconSize
            filled: root.kind === "folder"
            color: root.kind === "folder" ? Theme.inkSecondaryContainer
                 : root.kind === "archive" || root.kind === "app" ? Theme.inkTertiaryContainer
                 : root.kind === "image" || root.kind === "video" ? Theme.inkPrimaryContainer : Theme.textDim
        }
    }
    Image {
        id: img
        anchors.fill: parent
        visible: root.previewable && status === Image.Ready
        asynchronous: true
        cache: true
        fillMode: Image.PreserveAspectCrop
        // Decode at the size shown, in two buckets so zooming doesn't reload constantly (cache files stay 256 px)
        sourceSize.width: root.width <= 128 ? 128 : 256
        source: root.previewable ? "file://" + Fs.thumbPath(root.item.path) : ""
        onStatusChanged: if (status === Image.Error && root.previewable) Fs.requestThumb(root.item.path)
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: mask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
    }
    Rectangle { id: mask; width: root.width; height: root.height; radius: root.radius; visible: false; layer.enabled: true }
    Connections {
        target: Fs
        function onThumbReady(path) {
            if (path !== root.item.path) return;
            img.source = "";
            img.source = "file://" + Fs.thumbPath(root.item.path);
        }
    }
    Rectangle {
        visible: root.kind === "video" && img.visible
        anchors.centerIn: parent
        width: 36; height: 36; radius: 18
        color: Theme.alpha(Theme.surfaceLowest, 0.6)
        Icon { anchors.centerIn: parent; name: "play_arrow"; filled: true; size: 22 }
    }
}
