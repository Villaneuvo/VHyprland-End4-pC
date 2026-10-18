import QtQuick
import QtQuick.Effects

// Preview of an item: a thumbnail for images/videos (shared freedesktop cache), else a kind icon on a tonal tile.
Item {
    id: root
    required property var item
    property real radius: Theme.rThumb
    property real iconSize: Math.min(width, height) * 0.36
    readonly property string kind: Fs.kindOf(item)
    readonly property bool previewable: Fs.canThumb(item)
    // Photos, frames and covers fill the tile; pages and glyph sheets are fitted so they read as a whole
    readonly property bool crop: kind === "image" || kind === "video" || kind === "audio"
    property bool ready: false

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: !img.visible || !root.crop
        color: root.kind === "folder" ? Theme.secondaryContainer
             : root.kind === "image" || root.kind === "video" ? Theme.primaryContainer
             : root.kind === "archive" || root.kind === "app" ? Theme.tertiaryContainer
             : Theme.surfaceHighest
        Icon {
            anchors.centerIn: parent
            visible: !img.visible
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
        anchors.margins: root.crop ? 0 : Math.round(Math.min(root.width, root.height) * 0.12)
        visible: root.previewable && status === Image.Ready
        asynchronous: true
        cache: true
        fillMode: root.crop ? Image.PreserveAspectCrop : Image.PreserveAspectFit
        // Decode at the size shown, in two buckets so zooming doesn't reload constantly (cache files stay 256 px)
        sourceSize.width: root.width <= 128 ? 128 : 256
        source: root.previewable ? "file://" + Fs.thumbPath(root.item.path) : ""
        onStatusChanged: if (status === Image.Error && root.previewable) Fs.requestThumb(root.item.path, root.kind)
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
        visible: (root.kind === "video" || root.kind === "audio") && img.visible
        anchors.centerIn: parent
        width: 36; height: 36; radius: 18
        color: Theme.alpha(Theme.surfaceLowest, 0.6)
        Icon { anchors.centerIn: parent; name: root.kind === "audio" ? "music_note" : "play_arrow"; filled: true; size: 22 }
    }
}
