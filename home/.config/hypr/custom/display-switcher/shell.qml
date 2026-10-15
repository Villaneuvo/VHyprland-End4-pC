// Win+P style display-mode picker styled like end4-pC (matugen colors, Google Sans Flex, M3 shapes),
// dressed up with Himeko (Honkai: Star Rail) art from the user's himeko preset (copied into ./assets).
// Launched by ../scripts/display-mode.sh, which passes the monitor names and current mode via env.
// Lives outside ~/.config/quickshell so dots-hyprland updates (rsync --delete) can't wipe it.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

ShellRoot {
    id: root

    readonly property string here: Quickshell.env("HOME") + "/.config/hypr/custom/display-switcher"
    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/custom/scripts/display-mode.sh"
    readonly property string laptopName: Quickshell.env("DISPLAY_LAPTOP") || "eDP-1"
    readonly property string extName: Quickshell.env("DISPLAY_EXT") || "Monitor"
    readonly property string extModel: Quickshell.env("DISPLAY_EXT_MODEL") || extName
    readonly property string current: Quickshell.env("DISPLAY_CURRENT") || ""
    // Display numbers follow the primary chosen in Display Settings (cursor:default_monitor)
    readonly property bool extIsPrimary: Quickshell.env("DISPLAY_PRIMARY") === extName
    readonly property string lapNum: extIsPrimary ? "2" : "1"
    readonly property string monNum: extIsPrimary ? "1" : "2"

    readonly property var modes: [
        { id: "laptop", label: "PC screen only", hint: "Monitor turned off", left: true, right: false },
        { id: "mirror", label: "Duplicate", hint: "Same picture on both", left: true, right: true },
        { id: "extend", label: "Extend", hint: "Your desk layout", left: true, right: true },
        { id: "external", label: "Second screen only", hint: "Laptop turned off", left: false, right: true }
    ]
    // Himeko's line changes with the highlighted card (original lines, not game quotes)
    readonly property var himekoLines: ({
        "laptop": "Traveling light. One screen, one cup of coffee.",
        "mirror": "Let the whole crew read the same star map.",
        "extend": "More room to work means more coffee, too.",
        "external": "Big screen on the bridge. The laptop can rest."
    })
    property int focusIndex: Math.max(0, modes.findIndex(m => m.id === current))
    property bool shown: false

    FileView {
        id: colorsFile
        path: Quickshell.env("HOME") + "/.local/state/quickshell/user/generated/colors.json"
        blockLoading: true
    }
    readonly property var palette: {
        try { return JSON.parse(colorsFile.text()); } catch (e) { return {}; }
    }
    function col(key, fallback) { return palette[key] ?? fallback; }

    readonly property string fontMain: "Google Sans Flex"
    readonly property string fontIcon: "Material Symbols Rounded"

    function apply(modeId) {
        Quickshell.execDetached([root.script, modeId]);
        Qt.quit();
    }

    PanelWindow {
        id: win
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "display-switcher"

        Component.onCompleted: root.shown = true

        // Scrim: click anywhere outside the card to cancel
        Rectangle {
            anchors.fill: parent
            color: root.col("scrim", "#000000")
            opacity: root.shown ? 0.45 : 0
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            MouseArea { anchors.fill: parent; onClicked: Qt.quit() }
        }

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => {
                const n = root.modes.length;
                if (event.key === Qt.Key_Escape) Qt.quit();
                else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) root.focusIndex = (root.focusIndex + 1) % n;
                else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) root.focusIndex = (root.focusIndex + n - 1) % n;
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) root.apply(root.modes[root.focusIndex].id);
                else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_4) root.apply(root.modes[event.key - Qt.Key_1].id);
                else return;
                event.accepted = true;
            }
        }

        Item {
            id: cardBox
            anchors.centerIn: parent
            width: tiles.implicitWidth + 48
            height: card.height
            opacity: root.shown ? 1 : 0
            scale: root.shown ? 1 : 0.94
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

            ClippingRectangle {
                id: card
                width: parent.width
                height: banner.height + body.implicitHeight + 22
                radius: 30
                color: root.col("surface_container", "#271d1d")

                MouseArea { anchors.fill: parent } // keep clicks on the card from reaching the scrim

                // Banner: Himeko with her coffee, fading into the card
                Item {
                    id: banner
                    width: parent.width
                    height: 132
                    clip: true
                    Image {
                        // Scale to the card width and slide up so her face and coffee cup sit in the strip
                        width: parent.width
                        height: width * 414 / 735
                        y: -height * 0.2
                        source: "file://" + root.here + "/assets/himeko-banner.jpg"
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 800
                        asynchronous: true
                    }
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.alpha(root.col("surface_container", "#271d1d"), 0.05) }
                            GradientStop { position: 0.55; color: Qt.alpha(root.col("surface_container", "#271d1d"), 0.45) }
                            GradientStop { position: 1.0; color: root.col("surface_container", "#271d1d") }
                        }
                    }
                    Column {
                        anchors { left: parent.left; bottom: parent.bottom; leftMargin: 26; bottomMargin: 6 }
                        spacing: 0
                        Text {
                            text: "ASTRAL EXPRESS · NAVIGATION"
                            font.family: root.fontMain
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1.6
                            color: root.col("primary", "#ffb3b0")
                        }
                        Text {
                            text: "Display Navigation"
                            font.family: root.fontMain
                            font.pixelSize: 26
                            font.weight: Font.DemiBold
                            color: root.col("on_surface", "#f0dedd")
                        }
                        Text {
                            text: "Laptop · " + root.extModel + " (" + root.extName + ")"
                            font.family: root.fontMain
                            font.pixelSize: 13
                            color: root.col("on_surface_variant", "#d7c1c0")
                        }
                    }
                }

                Column {
                    id: body
                    anchors { top: banner.bottom; topMargin: 14; horizontalCenter: parent.horizontalCenter }
                    spacing: 16

                    // Himeko's comment on the highlighted mode
                    Rectangle {
                        width: tiles.implicitWidth
                        height: 40
                        radius: 20
                        color: root.col("surface_container_high", "#322827")
                        Row {
                            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                            spacing: 10
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "coffee"
                                font.family: root.fontIcon
                                font.pixelSize: 20
                                color: root.col("primary", "#ffb3b0")
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "<b>Himeko</b>  “" + root.himekoLines[root.modes[root.focusIndex].id] + "”"
                                textFormat: Text.StyledText
                                font.family: root.fontMain
                                font.pixelSize: 13
                                color: root.col("on_surface_variant", "#d7c1c0")
                            }
                        }
                    }

                    Row {
                        id: tiles
                        spacing: 10
                        Repeater {
                            model: root.modes
                            delegate: Rectangle {
                                id: tile
                                required property var modelData
                                required property int index
                                readonly property bool isCurrent: modelData.id === root.current
                                readonly property bool isFocus: index === root.focusIndex
                                readonly property color ink: isCurrent ? root.col("on_primary_container", "#ffdad8") : root.col("on_surface", "#f0dedd")
                                readonly property color lit: isCurrent ? root.col("on_primary_container", "#ffdad8") : root.col("primary", "#ffb3b0")
                                readonly property color dim: root.col("outline_variant", "#524342")

                                width: 168; height: 168
                                radius: isFocus ? 23 : 17
                                color: isCurrent ? root.col("primary_container", "#733333")
                                     : (hover.hovered || isFocus) ? root.col("surface_container_highest", "#3d3232")
                                     : root.col("surface_container_high", "#322827")
                                border.width: isFocus ? 2 : 0
                                border.color: root.col("primary", "#ffb3b0")
                                Behavior on radius { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 140 } }

                                HoverHandler { id: hover; onHoveredChanged: if (hovered) root.focusIndex = tile.index }
                                TapHandler { onTapped: root.apply(tile.modelData.id) }

                                // Shortcut digit
                                Rectangle {
                                    x: 12; y: 12; width: 22; height: 22; radius: 11
                                    color: tile.isCurrent ? root.col("primary", "#ffb3b0") : root.col("surface_container", "#271d1d")
                                    Text {
                                        anchors.centerIn: parent
                                        text: tile.index + 1
                                        font.family: root.fontMain
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        color: tile.isCurrent ? root.col("on_primary", "#571d1e") : root.col("on_surface_variant", "#d7c1c0")
                                    }
                                }
                                // Current mode: Himeko's star motif instead of a plain check
                                Text {
                                    visible: tile.isCurrent
                                    anchors { right: parent.right; top: parent.top; margins: 11 }
                                    text: "star"
                                    // Same recipe as end4-pC's MaterialSymbol: the default renderer
                                    // draws the FILL axis half-filled
                                    renderType: Text.NativeRendering
                                    font.family: root.fontIcon
                                    font.hintingPreference: Font.PreferNoHinting
                                    font.weight: Font.DemiBold
                                    font.variableAxes: ({ "FILL": 1, "opsz": 21 })
                                    font.pixelSize: 21
                                    color: root.col("primary", "#ffb3b0")
                                }

                                // Illustration: laptop on the left, external monitor on the right
                                Item {
                                    id: art
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 44
                                    width: 112; height: 60
                                    readonly property bool mirror: tile.modelData.id === "mirror"
                                    readonly property bool extend: tile.modelData.id === "extend"

                                    Rectangle {
                                        id: lap
                                        x: 0; y: 8; width: 50; height: 32; radius: 5
                                        color: tile.modelData.left ? tile.lit : "transparent"
                                        border.width: tile.modelData.left ? 0 : 1.5
                                        border.color: tile.dim
                                        Text {
                                            anchors.centerIn: parent
                                            visible: tile.modelData.left && (art.mirror || art.extend)
                                            text: root.lapNum
                                            font.family: root.fontMain; font.pixelSize: 15; font.weight: Font.Bold
                                            color: root.col("primary_container", "#733333")
                                        }
                                    }
                                    Rectangle {
                                        anchors.horizontalCenter: lap.horizontalCenter
                                        y: lap.y + lap.height + 2; width: 60; height: 4; radius: 2
                                        color: tile.modelData.left ? tile.lit : tile.dim
                                        opacity: tile.modelData.left ? 0.85 : 0.6
                                    }
                                    Rectangle {
                                        id: mon
                                        x: 60; y: 0; width: 52; height: 36; radius: 5
                                        color: tile.modelData.right ? tile.lit : "transparent"
                                        border.width: tile.modelData.right ? 0 : 1.5
                                        border.color: tile.dim
                                        Text {
                                            anchors.centerIn: parent
                                            visible: tile.modelData.right && (art.mirror || art.extend)
                                            text: art.mirror ? root.lapNum : root.monNum
                                            font.family: root.fontMain; font.pixelSize: 15; font.weight: Font.Bold
                                            color: root.col("primary_container", "#733333")
                                        }
                                    }
                                    Rectangle {
                                        anchors.horizontalCenter: mon.horizontalCenter
                                        y: mon.y + mon.height; width: 4; height: 8
                                        color: tile.modelData.right ? tile.lit : tile.dim
                                        opacity: tile.modelData.right ? 0.85 : 0.6
                                    }
                                    Rectangle {
                                        anchors.horizontalCenter: mon.horizontalCenter
                                        y: mon.y + mon.height + 8; width: 22; height: 3; radius: 1.5
                                        color: tile.modelData.right ? tile.lit : tile.dim
                                        opacity: tile.modelData.right ? 0.85 : 0.6
                                    }
                                }

                                Column {
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
                                    spacing: 2
                                    Text {
                                        width: parent.width
                                        text: tile.modelData.label
                                        font.family: root.fontMain
                                        font.pixelSize: 15
                                        font.weight: Font.DemiBold
                                        color: tile.ink
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: parent.width
                                        text: tile.modelData.hint
                                        font.family: root.fontMain
                                        font.pixelSize: 12
                                        color: tile.isCurrent ? tile.ink : root.col("on_surface_variant", "#d7c1c0")
                                        opacity: tile.isCurrent ? 0.85 : 1
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        width: tiles.implicitWidth
                        height: 32
                        Text {
                            anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                            text: "←  →  select   ·   1–4 quick pick   ·   Enter apply   ·   Esc cancel"
                            font.family: root.fontMain
                            font.pixelSize: 12
                            color: root.col("on_surface_variant", "#d7c1c0")
                            opacity: 0.8
                        }
                        // Full layout editor (nwg-displays): drag monitors, resolution, refresh, scale, rotation
                        Rectangle {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            width: arrangeRow.implicitWidth + 24
                            height: 32
                            radius: 16
                            color: arrangeHover.hovered ? root.col("secondary_container", "#5d3f3e") : root.col("surface_container_high", "#322827")
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Row {
                                id: arrangeRow
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "tune"
                                    font.family: root.fontIcon
                                    font.pixelSize: 18
                                    color: root.col("primary", "#ffb3b0")
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Arrange displays…"
                                    font.family: root.fontMain
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                    color: root.col("on_surface", "#f0dedd")
                                }
                            }
                            HoverHandler { id: arrangeHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    Quickshell.execDetached(["qs", "-p", root.here + "/settings.qml"]);
                                    Qt.quit();
                                }
                            }
                        }
                    }
                }
            }

            // Thin outline drawn over the clipped card
            Rectangle {
                anchors.fill: card
                radius: card.radius
                color: "transparent"
                border.width: 1
                border.color: root.col("outline_variant", "#524342")
            }

            // Chibi Himeko peeking over the banner edge (pops in a beat after the card)
            Rectangle {
                id: chibi
                width: 104; height: 104; radius: 52
                x: parent.width - width - 28
                y: banner.height - height + 26
                color: root.col("surface_container", "#271d1d")
                scale: root.shown ? 1 : 0.4
                opacity: root.shown ? 1 : 0
                Behavior on scale { SequentialAnimation { PauseAnimation { duration: 120 } NumberAnimation { duration: 380; easing.type: Easing.OutBack; easing.overshoot: 2.0 } } }
                Behavior on opacity { SequentialAnimation { PauseAnimation { duration: 120 } NumberAnimation { duration: 200 } } }
                ClippingRectangle {
                    anchors.fill: parent
                    anchors.margins: 4
                    radius: width / 2
                    border.width: 2
                    border.color: root.col("primary", "#ffb3b0")
                    Image {
                        anchors.fill: parent
                        source: "file://" + root.here + "/assets/himeko-chibi.jpg"
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 256
                        asynchronous: true
                    }
                }
            }
        }
    }
}
