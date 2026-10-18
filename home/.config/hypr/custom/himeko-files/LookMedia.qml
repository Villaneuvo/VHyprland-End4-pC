import QtQuick
import QtQuick.Layouts
import QtMultimedia

// Quick Look body for video and audio: plays at once (HF_MUTE silences it); click or the bar pauses, seeks, mutes.
Item {
    id: root
    required property var item
    required property bool video
    readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
    property bool muted: Theme.mute
    signal failed()
    // Card shape: the video's own; audio gets a fixed card for the cover, tags and controls
    readonly property real aspect: !video ? 0 : out.sourceRect.height > 0 ? out.sourceRect.width / out.sourceRect.height : 16 / 9
    readonly property real prefW: video ? 0 : 420
    readonly property real prefH: video ? 0 : 340

    function clock(ms) { const s = Math.floor(ms / 1000); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0"); }
    function toggle() { if (playing) player.pause(); else player.play(); }

    MediaPlayer {
        id: player
        source: Fs.uri(root.item.path)
        videoOutput: root.video ? out : null
        audioOutput: AudioOutput { muted: root.muted }
        onErrorOccurred: root.failed()
        onSourceChanged: play()     // stepping between media files reuses this body: start the new one
    }
    Component.onCompleted: player.play()
    Component.onDestruction: player.stop()

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        VideoOutput {
            id: out
            visible: root.video
            Layout.fillWidth: true
            Layout.fillHeight: true
            fillMode: VideoOutput.PreserveAspectFit
            MouseArea { anchors.fill: parent; onClicked: root.toggle() }
        }

        ColumnLayout {
            visible: !root.video
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Thumb {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height); height: width
                    item: root.item
                    iconSize: width * 0.45
                }
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: player.metaData.stringValue(MediaMetaData.Title) || root.item.name
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: 600
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                visible: text !== ""
                text: player.metaData.stringValue(MediaMetaData.ContributingArtist) || player.metaData.stringValue(MediaMetaData.AlbumArtist)
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13
            }
        }

        // Controls: play/pause, seek, time, mute
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            IconButton { icon: root.playing ? "pause" : "play_arrow"; tip: root.playing ? "Pause" : "Play"; onClicked: root.toggle() }
            Item {
                Layout.fillWidth: true
                implicitHeight: 28
                Rectangle {
                    id: track
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width; height: 4; radius: 2
                    color: Theme.alpha(Theme.text, 0.18)
                    Rectangle {
                        width: player.duration > 0 ? parent.width * player.position / player.duration : 0
                        height: parent.height; radius: 2
                        color: Theme.primary
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    function seek(x) { if (player.duration > 0) player.position = Math.max(0, Math.min(1, x / width)) * player.duration; }
                    onPressed: (e) => seek(e.x)
                    onPositionChanged: (e) => { if (pressed) seek(e.x); }
                }
            }
            Text {
                text: root.clock(player.position) + " / " + root.clock(player.duration)
                color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12; font.features: { "tnum": 1 }
            }
            IconButton { icon: root.muted ? "volume_off" : "volume_up"; tip: root.muted ? "Unmute (M)" : "Mute (M)"; onClicked: root.muted = !root.muted }
        }
    }
}
