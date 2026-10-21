import QtQuick

// The operations button (GNOME Files' header pie): a ring that fills as copies and moves run, spinning while they
// count or for jobs without byte counts; a check when everything is done. Clicking it toggles the popover (Browser).
MouseArea {
    id: root
    signal toggled()
    readonly property var running: Fs.jobs.filter(j => j.state === "scanning" || j.state === "running")
    readonly property bool busy: running.length > 0
    readonly property bool indeterminate: running.some(j => j.state === "scanning" || !j.total)
    readonly property real fraction: {
        const total = running.reduce((s, j) => s + j.total, 0);
        return total ? running.reduce((s, j) => s + j.bytes, 0) / total : 0;
    }
    readonly property string icon: !busy ? (Fs.jobs.some(j => j.state === "failed") ? "error" : "check")
        : running.every(j => j.kind === "trash" || j.kind === "delete") ? "delete" : "arrow_downward"
    implicitWidth: 44; implicitHeight: 44
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: toggled()
    onFractionChanged: ring.requestPaint()
    onBusyChanged: ring.requestPaint()
    onIndeterminateChanged: ring.requestPaint()

    Rectangle { anchors.fill: parent; radius: width / 2; color: root.containsMouse ? Theme.hover : "transparent" }
    Canvas {
        id: ring
        anchors.fill: parent
        anchors.margins: 5
        onPaint: {
            const c = getContext("2d"), r = width / 2 - 2.5;
            c.reset();
            c.lineWidth = 3;
            c.lineCap = "round";
            c.strokeStyle = Theme.alpha(Theme.text, 0.12);
            c.beginPath(); c.arc(width / 2, height / 2, r, 0, 2 * Math.PI); c.stroke();
            c.strokeStyle = Theme.primary;
            c.beginPath();
            const sweep = root.indeterminate ? 0.5 * Math.PI : root.busy ? Math.max(0.04, root.fraction) * 2 * Math.PI : 2 * Math.PI;
            c.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + sweep);
            c.stroke();
        }
        RotationAnimator on rotation {
            running: root.indeterminate && root.visible
            from: 0; to: 360; duration: 1100; loops: Animation.Infinite
            onRunningChanged: if (!running) ring.rotation = 0
        }
    }
    Icon { anchors.centerIn: parent; name: root.icon; size: 18; color: root.busy ? Theme.text : Theme.primary }

    Accessible.role: Accessible.Button
    Accessible.name: "Operations"
}
