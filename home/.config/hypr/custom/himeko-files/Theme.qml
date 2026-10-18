pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Himeko Glass tokens. Colors come live from end4-pC's matugen output, so the app follows the wallpaper.
Singleton {
    id: root
    readonly property string home: Quickshell.env("HOME")

    FileView {
        id: colorsFile
        path: root.home + "/.local/state/quickshell/user/generated/colors.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
    }
    readonly property var p: {
        try { return JSON.parse(colorsFile.text()); } catch (e) { return {}; }
    }
    function c(key, fallback) { return p[key] ?? fallback; }
    function alpha(color, a) { const q = Qt.color(color); return Qt.rgba(q.r, q.g, q.b, a); }

    readonly property color primary: c("primary", "#FFB3B0")
    readonly property color inkPrimary: c("on_primary", "#561D1E")
    readonly property color primaryContainer: c("primary_container", "#733333")
    readonly property color inkPrimaryContainer: c("on_primary_container", "#FFDAD8")
    readonly property color secondaryContainer: c("secondary_container", "#5D3F3E")
    readonly property color inkSecondaryContainer: c("on_secondary_container", "#FFDAD8")
    readonly property color tertiary: c("tertiary", "#E3C28C")
    readonly property color tertiaryContainer: c("tertiary_container", "#5A4316")
    readonly property color inkTertiaryContainer: c("on_tertiary_container", "#FFDEAB")
    readonly property color error: c("error", "#FFB4AB")
    readonly property color surface: c("surface", "#1A1111")
    readonly property color surfaceLowest: c("surface_container_lowest", "#140C0C")
    readonly property color surfaceLow: c("surface_container_low", "#231919")
    readonly property color surfaceMid: c("surface_container", "#271D1D")
    readonly property color surfaceHigh: c("surface_container_high", "#322827")
    readonly property color surfaceHighest: c("surface_container_highest", "#3D3232")
    readonly property color text: c("on_surface", "#F0DEDD")
    readonly property color textDim: c("on_surface_variant", "#D7C1C0")
    readonly property color outline: c("outline", "#A08C8B")
    readonly property color outlineVariant: c("outline_variant", "#524342")

    // Glass recipe (see the design canvas): chrome 62 %, menus 97 %, content 86 %
    readonly property color chrome: alpha(surfaceMid, 0.62)
    readonly property color chromeStrong: alpha(surfaceMid, 0.80)
    readonly property color menu: alpha(surfaceHigh, 0.97)
    readonly property color content: alpha(surface, 0.86)
    readonly property color edge: alpha(inkPrimaryContainer, 0.12)
    readonly property color hover: alpha(text, 0.08)
    readonly property color pressed: alpha(text, 0.14)

    readonly property string font: "Google Sans Flex"
    readonly property string iconFont: "Material Symbols Rounded"
    readonly property string mono: "JetBrainsMono Nerd Font"

    readonly property int rWindow: 22
    readonly property int rPanel: 16
    readonly property int rTile: 22
    readonly property int rThumb: 16
    readonly property int rRow: 14
    readonly property int target: 44

    // ---- motion: end4-pC's curves (Appearance.qml), so the app moves like the shell ----
    readonly property var curve: ({
        fastSpatial: [0.42, 1.67, 0.21, 0.90, 1, 1],   // overshoot, for things that pop
        spatial: [0.38, 1.21, 0.22, 1.00, 1, 1],
        effects: [0.34, 0.80, 0.34, 1.00, 1, 1],       // fades and color
        enter: [0.05, 0.7, 0.1, 1, 1, 1]
    })
    readonly property var duration: ({ fastSpatial: 350, spatial: 500, effects: 200, enter: 400 })
    // Off when GNOME's "enable-animations" or Hyprland's animations are off; HF_ANIMATE=0 forces it (tests)
    property bool animate: Quickshell.env("HF_ANIMATE") !== "0"
    // HF_MUTE=1 silences Quick Look media (tests: never play sound through the user's speakers)
    readonly property bool mute: Quickshell.env("HF_MUTE") === "1"
    function dur(kind) { return animate ? duration[kind] : 0; }
    Process {
        running: Quickshell.env("HF_ANIMATE") !== "0"
        command: ["bash", "-c", "gsettings get org.gnome.desktop.interface enable-animations; hyprctl getoption animations:enabled -j | jq '.bool // .int'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                root.animate = l[0] !== "false" && l[1] !== "false" && l[1] !== "0";
            }
        }
    }
}
