import QtQuick
import QtQuick.Layouts

// gvfs asks through network.py (Fs.netAsk): a password, laid out like GNOME's "Authentication Required" dialog, or a
// question with gvfs' own choices. `req` is the ask plus reply(answer); every answer clears the password and closes.
FocusScope {
    id: root
    required property var req
    property Item backdrop
    signal done()

    readonly property bool question: req.ask === "question"
    property bool anonymous: false
    property string remember: "never"           // never | session | permanently (Forget Immediately is GTK's default)
    property bool choosing: false               // the Remember Password popover
    readonly property var rememberLabels: ({ never: "Forget Immediately", session: "Until Logout", permanently: "Forever" })

    function answer(a) {
        const r = req;
        pass.text = "";
        try { r.reply(a); } finally { done(); }   // a helper that just died can't take the answer: close anyway
    }
    function connectNow() { answer({ user: user.text, domain: domain.text, password: pass.text, anonymous: anonymous, save: remember }); }
    function cancel() { answer({ cancel: true }); }
    function choose(i) { answer({ choice: i }); }
    // Test hooks (Browser IPC)
    function state() {
        return { title: req.title, message: req.message, question: question, choices: question ? req.choices : [],
                 connectAs: !question && req.anonymous, user: user.show, domain: domain.show, password: pass.show, remember: rememberRow.show };
    }
    function fill(f) {
        if (f.user !== undefined) user.text = f.user;
        if (f.domain !== undefined) domain.text = f.domain;
        if (f.password !== undefined) pass.text = f.password;
        if (f.anonymous !== undefined) anonymous = f.anonymous;
        if (f.remember !== undefined) remember = f.remember;
    }
    function press(label) {
        if (label === "Cancel") return cancel();
        if (!question && label === "Connect") return connectNow();
        const i = question ? req.choices.indexOf(label) : -1;
        if (i >= 0) choose(i);
    }

    // Modal: no key reaches the window behind (Ctrl+W, F5, Alt+Left would pull the folder away from under the dialog)
    Keys.onPressed: (e) => {
        if (e.key === Qt.Key_Escape) choosing ? choosing = false : cancel();
        else if (!question && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)) connectNow();
        e.accepted = true;
    }
    Component.onCompleted: (user.show && !user.text ? user : pass.show ? pass : root).forceActiveFocus()

    Rectangle { anchors.fill: parent; color: Theme.alpha(Theme.surfaceLowest, 0.45) }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: (e) => e.accepted = true }   // modal

    Glass {
        id: card
        backdrop: root.backdrop
        anchors.centerIn: parent
        width: Math.min(420, root.width * 0.9)
        height: col.implicitHeight + 40
        radius: Theme.rPanel
        tint: Theme.alpha(Theme.surfaceMid, 0.94)
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: root.choosing = false }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            spacing: 14
            Icon { Layout.alignment: Qt.AlignHCenter; name: root.question ? "help" : "lock"; size: 34; color: Theme.primary }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.req.title
                textFormat: Text.PlainText   // gvfs' words, which quote server names
                wrapMode: Text.Wrap
                color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: 650
            }
            Text {
                visible: text !== ""
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.req.message.trim()
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: Theme.textDim; font.family: Theme.font; font.pixelSize: 13
            }

            // Connect As: Anonymous / Registered User
            RowLayout {
                visible: !root.question && root.req.anonymous
                Layout.fillWidth: true
                spacing: 10
                Text { text: "Connect As"; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; Layout.fillWidth: true }
                Rectangle {
                    implicitWidth: seg.implicitWidth + 8; implicitHeight: 38; radius: 19
                    color: Theme.alpha(Theme.text, 0.06)
                    Row {
                        id: seg
                        anchors.centerIn: parent
                        spacing: 4
                        Repeater {
                            model: [["Anonymous", true], ["Registered User", false]]
                            delegate: IconButton {
                                required property var modelData
                                implicitHeight: 30
                                label: modelData[0]
                                active: root.anonymous === modelData[1]
                                onClicked: root.anonymous = modelData[1]
                            }
                        }
                    }
                }
            }

            PropGroup {
                visible: !root.question && (user.show || domain.show || pass.show || rememberRow.show)
                EntryRow { id: user; title: "Username"; text: root.req.user ?? ""; show: !root.question && root.req.needUser && !root.anonymous }
                EntryRow { id: domain; title: "Domain"; text: root.req.domain ?? ""; show: !root.question && root.req.needDomain && !root.anonymous }
                EntryRow { id: pass; title: "Password"; secret: true; show: !root.question && root.req.needPassword && !root.anonymous }
                PropRow {
                    id: rememberRow
                    kind: "dropdown"; title: "Remember Password"; value: root.rememberLabels[root.remember]
                    show: !root.question && root.req.canSave && !root.anonymous
                    visible: show
                    onClicked: root.choosing = !root.choosing
                }
            }

            // Buttons: Cancel / Connect, or one per gvfs choice
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8
                Item { Layout.fillWidth: true }
                IconButton {
                    visible: !root.question
                    label: "Cancel"; bg: containsMouse ? Theme.hover : Theme.alpha(Theme.text, 0.08)
                    onClicked: root.cancel()
                }
                IconButton { visible: !root.question; label: "Connect"; active: true; onClicked: root.connectNow() }
                Repeater {
                    model: root.question ? root.req.choices : []
                    delegate: IconButton {
                        required property string modelData
                        required property int index
                        label: modelData
                        active: index === 0
                        bg: active ? Theme.primary : containsMouse ? Theme.hover : Theme.alpha(Theme.text, 0.08)
                        onClicked: root.choose(index)
                    }
                }
            }
        }

        // Remember Password popover, under its row
        Glass {
            visible: root.choosing
            backdrop: root.backdrop
            tint: Theme.alpha(Theme.surfaceHigh, 0.97)
            radius: 12
            readonly property point at: rememberRow.mapToItem(card, 0, rememberRow.height + 6)
            x: card.width - width - 20; y: at.y
            width: 220; height: pop.implicitHeight + 12
            ColumnLayout {
                id: pop
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                spacing: 2
                Repeater {
                    model: ["never", "session", "permanently"]
                    delegate: PropRow {
                        required property string modelData
                        kind: "choice"; title: root.rememberLabels[modelData]; checked: root.remember === modelData
                        onClicked: { root.remember = modelData; root.choosing = false; }
                    }
                }
            }
        }
    }

    // A boxed entry row: small dim title above the field (GNOME's AdwEntryRow look)
    component EntryRow: Rectangle {
        id: entry
        property string title
        property alias text: input.text
        property bool secret: false
        property bool show: true
        visible: show
        Layout.fillWidth: true
        implicitHeight: 56
        color: input.activeFocus ? Theme.alpha(Theme.text, 0.08) : Theme.alpha(Theme.text, 0.05)
        function forceActiveFocus() { input.forceActiveFocus(); }
        Text {
            x: 14; y: 8
            text: entry.title
            color: input.activeFocus ? Theme.primary : Theme.textDim
            font.family: Theme.font; font.pixelSize: 12
        }
        TextInput {
            id: input
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 14; rightMargin: 14; bottomMargin: 9 }
            echoMode: entry.secret ? TextInput.Password : TextInput.Normal
            clip: true
            color: Theme.text
            selectionColor: Theme.primary; selectedTextColor: Theme.inkPrimary
            font.family: Theme.font; font.pixelSize: 14
            selectByMouse: true
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onPressed: (m) => { input.forceActiveFocus(); m.accepted = false; } }
    }
}
