// Himeko Files: a file manager in the "Himeko Glass" design (see README), built on Quickshell like end4-pC.
// Launch: ~/.config/hypr/custom/himeko-files/himeko-files [FOLDER]
import QtQuick
import Quickshell

ShellRoot {
    FloatingWindow {
        id: win
        // HF_TITLE lets dev tools tell their test window apart from yours ("Files (test)")
        title: (Quickshell.env("HF_TITLE") || "Files") + " — " + browser.title
        color: "transparent"
        implicitWidth: 1248
        implicitHeight: 788
        onClosed: browser.windowClosed()   // jobs still running finish first
        Browser {
            id: browser
            anchors.fill: parent
            startPath: Quickshell.env("HF_PATH") || Fs.home
            startAddress: Quickshell.env("HF_ADDRESS") || ""
            focus: true
        }
    }
}
