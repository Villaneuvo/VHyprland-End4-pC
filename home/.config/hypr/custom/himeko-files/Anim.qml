import QtQuick

// A NumberAnimation on one of the motion tokens:  Behavior on scale { Anim { kind: "fastSpatial" } }
NumberAnimation {
    property string kind: "effects"
    duration: Theme.dur(kind)
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Theme.curve[kind]
}
