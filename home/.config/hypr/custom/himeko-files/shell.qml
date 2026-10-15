// Himeko Files: a file manager in the "Himeko Glass" design (see README), built on Quickshell like end4-pC.
// Launch: ~/.config/hypr/custom/himeko-files/himeko-files [FOLDER]
import QtQuick
import Quickshell

ShellRoot {
    FloatingWindow {
        id: win
        title: "Files — " + browser.title
        color: "transparent"
        implicitWidth: 1248
        implicitHeight: 788
        Browser {
            id: browser
            anchors.fill: parent
            startPath: Quickshell.env("HF_PATH") || Fs.home
            focus: true
        }
    }
}
