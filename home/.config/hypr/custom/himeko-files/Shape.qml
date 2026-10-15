import QtQuick
import QtQuick.Shapes

// Expressive Material shapes that carry state: "cookie" = selected, "flower" = favorite/default,
// "burst" = count/new, "circle" otherwise. A wobbly circle: r(t) = R(1 - a) + R·a·(1 + cos(n·t)) / 2.
Shape {
    id: root
    property string kind: "cookie"
    property color color: Theme.primary
    readonly property var spec: ({ cookie: [9, 0.14], flower: [6, 0.20], burst: [12, 0.24], circle: [1, 0] })[kind] ?? [1, 0]
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
        strokeWidth: -1
        fillColor: root.color
        PathPolyline {
            path: {
                const pts = [], n = root.spec[0], a = root.spec[1], steps = 96;
                const R = Math.min(root.width, root.height) / 2, cx = root.width / 2, cy = root.height / 2;
                for (let i = 0; i <= steps; i++) {
                    const t = 2 * Math.PI * i / steps - Math.PI / 2;
                    const r = R * (1 - a) + R * a * (1 + Math.cos(n * (t + Math.PI / 2))) / 2;
                    pts.push(Qt.point(cx + r * Math.cos(t), cy + r * Math.sin(t)));
                }
                return pts;
            }
        }
    }
}
