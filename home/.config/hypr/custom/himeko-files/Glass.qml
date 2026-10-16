import QtQuick
import QtQuick.Effects

// A frosted capsule: blurs whatever part of `backdrop` lies under it, then tints it.
// Liquid-Glass rule: only the chrome floats on glass; content stays solid.
Item {
    id: root
    property Item backdrop
    property color tint: Theme.chrome
    property real radius: height / 2
    property bool border: true

    ShaderEffectSource {
        id: src
        visible: false
        sourceItem: root.backdrop
        live: true
        recursive: false
        sourceRect: {
            if (!root.backdrop) return Qt.rect(0, 0, 0, 0);
            void root.x; void root.y; void root.width; void root.height;
            const p = root.mapToItem(root.backdrop, 0, 0);
            return Qt.rect(p.x, p.y, root.width, root.height);
        }
    }
    Rectangle { id: mask; anchors.fill: parent; radius: root.radius; visible: false; layer.enabled: true }
    MultiEffect {
        anchors.fill: parent
        source: src
        visible: root.backdrop !== null
        blurEnabled: true
        blur: 1.0
        blurMax: 40
        saturation: 0.2
        maskEnabled: true
        maskSource: mask
    }
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.tint
        Behavior on color { ColorAnimation { duration: Theme.dur("effects") } }
    }
    Sheen { radius: root.radius; edge: root.border ? 0.12 : 0 }
}
