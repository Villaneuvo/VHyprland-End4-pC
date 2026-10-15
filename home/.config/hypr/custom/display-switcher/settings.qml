// Display Settings: GNOME-style monitor arranger styled like end4-pC and the Super+Alt+P picker
// (matugen colors, Google Sans Flex, M3 shapes, Himeko art from ./assets).
// Reads `hyprctl monitors all -j`, writes ~/.config/hypr/monitors.lua (loaded by hyprland.lua) and reloads.
// Apply asks "Keep these settings?" and reverts on its own after 15 s, like GNOME/Windows.
// Launch: qs -p ~/.config/hypr/custom/display-switcher/settings.qml
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string here: home + "/.config/hypr/custom/display-switcher"
    readonly property string monitorsFile: home + "/.config/hypr/monitors.lua"
    readonly property string nwgDisplays: home + "/.local/share/nwg-displays-venv/bin/nwg-displays"

    // ---- Theme (same source as end4-pC: matugen output) ----
    FileView {
        id: colorsFile
        path: root.home + "/.local/state/quickshell/user/generated/colors.json"
        blockLoading: true
    }
    readonly property var palette: {
        try { return JSON.parse(colorsFile.text()); } catch (e) { return {}; }
    }
    function col(key, fallback) { return palette[key] ?? fallback; }
    readonly property string fontMain: "Google Sans Flex"
    readonly property string fontIcon: "Material Symbols Rounded"

    // ---- State ----
    property var mons: []       // working copy edited by the UI
    property var original: []   // what is live right now
    property int sel: 0
    readonly property var cur: mons[sel] ?? null
    // Hyprland has no real "primary display". Here it means: shown as display 1, workspace 1 opens there,
    // and the cursor starts there (see luaText()). Read back from cursor:default_monitor.
    property string primary: ""
    property string originalPrimary: ""
    property string savedPrimary: ""   // raw value from `hyprctl getoption cursor:default_monitor`
    readonly property bool dirty: JSON.stringify(mons) !== JSON.stringify(original) || primary !== originalPrimary
    property int countdown: 0   // > 0 while the "keep settings?" prompt is up
    property bool busy: false
    property bool identifying: false

    // Display numbers: primary first, then the built-in screen, then by port name
    readonly property var order: {
        const idx = mons.map((m, i) => i);
        idx.sort((a, b) => (mons[b].name === primary) - (mons[a].name === primary)
            || (mons[b].internal - mons[a].internal) || mons[a].name.localeCompare(mons[b].name));
        return idx;
    }
    function numberOf(i) { return order.indexOf(i) + 1; }
    function makePrimary() { if (cur && cur.enabled) primary = cur.name; }

    function isInternal(name) { return /^(eDP|LVDS|DSI)/.test(name); }
    function round2(v) { return Math.round(v * 100) / 100; }
    function lw(m) { return Math.round(((m.transform % 2) ? m.h : m.w) / m.scale); }
    function lh(m) { return Math.round(((m.transform % 2) ? m.w : m.h) / m.scale); }

    function load(text) {
        let arr = [];
        try { arr = JSON.parse(text); } catch (e) { return; }
        const list = arr.map(m => {
            const seen = {};
            const modes = [];
            for (const s of m.availableModes) {
                const g = /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(s);
                if (!g) continue;
                const md = { w: +g[1], h: +g[2], r: round2(+g[3]) };
                const k = md.w + "x" + md.h + "@" + md.r;
                if (!seen[k]) { seen[k] = true; modes.push(md); }
            }
            return {
                name: m.name, desc: m.description, model: m.model || m.name,
                internal: isInternal(m.name), enabled: !m.disabled, modes: modes,
                w: m.width, h: m.height, r: round2(m.refreshRate),
                x: m.x, y: m.y, scale: round2(m.scale), transform: m.transform
            };
        });
        list.sort((a, b) => (b.internal - a.internal) || a.name.localeCompare(b.name));
        mons = list;
        original = JSON.parse(JSON.stringify(list));
        const saved = list.find(m => m.name === savedPrimary && m.enabled);
        const fallback = list.find(m => m.internal && m.enabled) ?? list.find(m => m.enabled) ?? list[0];
        primary = (saved ?? fallback)?.name ?? "";
        originalPrimary = primary;
        if (sel >= list.length) sel = 0;
    }

    function update(i, patch) {
        const a = mons.slice();
        a[i] = Object.assign({}, a[i], patch);
        mons = a;
    }

    function overlaps(i, x, y, W, H) {
        return mons.some((o, j) => j !== i && o.enabled
            && x < o.x + lw(o) && x + W > o.x && y < o.y + lh(o) && y + H > o.y);
    }

    // Snap monitor i next to another enabled monitor (touching edge, aligned start/center/end),
    // picking the spot closest to where it was dropped.
    function snapped(i, px, py) {
        const m = mons[i], W = lw(m), H = lh(m);
        let best = null, bestD = Infinity;
        for (let j = 0; j < mons.length; j++) {
            const o = mons[j];
            if (j === i || !o.enabled) continue;
            const ow = lw(o), oh = lh(o);
            const spots = [];
            for (const y of [o.y, o.y + (oh - H) / 2, o.y + oh - H]) { spots.push([o.x + ow, y]); spots.push([o.x - W, y]); }
            for (const x of [o.x, o.x + (ow - W) / 2, o.x + ow - W]) { spots.push([x, o.y + oh]); spots.push([x, o.y - H]); }
            for (const s of spots) {
                const sx = Math.round(s[0]), sy = Math.round(s[1]);
                if (overlaps(i, sx, sy, W, H)) continue;
                const d = Math.hypot(sx - px, sy - py);
                if (d < bestD) { bestD = d; best = [sx, sy]; }
            }
        }
        return best ?? [0, 0];
    }

    // Shift everything so the enabled layout starts at 0,0 (nwg-displays can't show negative positions)
    function normalized(list) {
        const en = list.filter(m => m.enabled);
        if (!en.length) return list;
        const mx = Math.min(...en.map(m => m.x)), my = Math.min(...en.map(m => m.y));
        return list.map(m => Object.assign({}, m, { x: m.x - mx, y: m.y - my }));
    }

    function place(i, px, py) {
        const p = snapped(i, px, py);
        update(i, { x: p[0], y: p[1] });
        mons = normalized(mons);
    }
    function resnap(i) { place(i, mons[i].x, mons[i].y); }

    function pick(key, value) {
        const m = cur;
        if (!m) return;
        if (key === "res") {
            const wh = value.split("x").map(Number);
            const rates = m.modes.filter(md => md.w === wh[0] && md.h === wh[1]).map(md => md.r);
            update(sel, { w: wh[0], h: wh[1], r: Math.max(...rates) });
            resnap(sel);
        } else if (key === "rate") {
            update(sel, { r: value });
        } else if (key === "scale") {
            update(sel, { scale: value });
            resnap(sel);
        } else if (key === "rot") {
            update(sel, { transform: value });
            resnap(sel);
        }
    }

    function toggleEnabled() {
        const m = cur;
        if (m.enabled && mons.filter(o => o.enabled).length === 1) return; // never turn off the last screen
        update(sel, { enabled: !m.enabled });
        if (!m.enabled) resnap(sel);
        mons = normalized(mons);
        if (m.enabled && primary === m.name) primary = mons.find(o => o.enabled).name; // primary must stay on
    }

    function luaText(list) {
        const q = s => '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
        const lines = [
            "-- Generated by Display Settings (~/.config/hypr/custom/display-switcher/settings.qml).",
            "-- Loaded by hyprland.lua; dots-hyprland updates don't touch this file. Previous version: monitors.lua.bak",
            "-- External monitors are matched by description, so they keep their settings on any port.",
            ""
        ];
        for (const m of list) {
            const out = m.internal ? m.name : "desc:" + m.desc;
            if (!m.enabled) lines.push("hl.monitor({ output = " + q(out) + ", disabled = true })");
            else lines.push("hl.monitor({ output = " + q(out) + ", mode = " + q(m.w + "x" + m.h + "@" + m.r.toFixed(2))
                + ", position = " + q(m.x + "x" + m.y) + ", scale = " + m.scale + ", transform = " + m.transform + " })");
        }
        const p = list.find(m => m.name === primary && m.enabled);
        if (p) {
            lines.push("",
                "-- Primary display (" + (p.internal ? "built-in" : p.model) + "): workspace 1 opens here, the cursor starts here.",
                "hl.workspace_rule({ workspace = \"1\", monitor = " + q(p.internal ? p.name : "desc:" + p.desc) + ", default = true })",
                "hl.config({ cursor = { default_monitor = " + q(p.name) + " } })");
        }
        return lines.join("\n") + "\n";
    }

    function apply() {
        if (!dirty || busy) return;
        busy = true;
        writer.command = ["bash", "-c",
            'if [ -f "$2" ]; then cp -f "$2" "$2.bak"; else rm -f "$2.bak"; fi; printf "%s" "$1" > "$2" && hyprctl reload',
            "_", luaText(mons), monitorsFile];
        writer.running = true;
    }
    function revert() {
        countdown = 0;
        busy = true;
        reverter.command = ["bash", "-c",
            'if [ -f "$1.bak" ]; then mv -f "$1.bak" "$1"; else rm -f "$1"; fi; hyprctl reload', "_", monitorsFile];
        reverter.running = true;
    }
    function keep() { countdown = 0; }

    Process {
        id: primaryQuery
        command: ["hyprctl", "getoption", "cursor:default_monitor"]
        stdout: StdioCollector { id: primaryOut }
        onExited: {
            const g = /^str:\s*(\S+)/m.exec(primaryOut.text);
            root.savedPrimary = g && g[1] !== "[[EMPTY]]" ? g[1] : "";
            query.running = true;
        }
    }
    Process {
        id: query
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector { id: queryOut }
        onExited: root.load(queryOut.text)
    }
    Timer { id: identifyTimer; interval: 3000; onTriggered: root.identifying = false }
    function identify() { identifying = true; identifyTimer.restart(); }

    // "Identify": a big number on every physical screen, matching the numbers in this window
    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            id: idWin
            required property var modelData
            readonly property int monIndex: root.mons.findIndex(m => m.name === idWin.modelData.name)
            readonly property var mon: monIndex >= 0 ? root.mons[monIndex] : null
            screen: modelData
            visible: root.identifying
            implicitWidth: 320
            implicitHeight: 320
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "display-identify"
            Rectangle {
                anchors.fill: parent
                radius: 56
                color: root.col("primary_container", "#733333")
                border.width: 3
                border.color: root.col("primary", "#ffb3b0")
                Column {
                    anchors.centerIn: parent
                    spacing: 2
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: idWin.monIndex >= 0 ? root.numberOf(idWin.monIndex) : "?"
                        font.family: root.fontMain; font.pixelSize: 160; font.weight: Font.Bold
                        color: root.col("on_primary_container", "#ffdad8")
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: idWin.mon ? (idWin.mon.internal ? "Built-in display" : idWin.mon.model) : idWin.modelData.name
                        font.family: root.fontMain; font.pixelSize: 18; font.weight: Font.DemiBold
                        color: root.col("on_primary_container", "#ffdad8")
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: idWin.mon !== null && idWin.mon.name === root.primary
                        text: "★ Primary display"
                        font.family: root.fontMain; font.pixelSize: 14
                        color: root.col("primary", "#ffb3b0")
                    }
                }
            }
        }
    }
    Process {
        id: writer
        onExited: { root.busy = false; root.countdown = 15; refresh.restart(); }
    }
    Process {
        id: reverter
        onExited: { root.busy = false; refresh.restart(); }
    }
    Timer { id: refresh; interval: 900; onTriggered: primaryQuery.running = true } // let Hyprland settle first
    Timer {
        interval: 1000; repeat: true; running: root.countdown > 0
        onTriggered: { root.countdown -= 1; if (root.countdown === 0) root.revert(); }
    }
    Component.onCompleted: primaryQuery.running = true

    // Himeko's line follows what you're doing (original lines, not game quotes)
    readonly property string himekoLine: countdown > 0 ? "New route plotted. Say the word and I'll lock it in."
        : dirty ? "Course changed. Hit Apply and I'll keep the old route ready, just in case."
        : "Drag the screens to match your desk. I'll handle the coordinates."

    FloatingWindow {
        id: win
        title: "Display Settings"
        implicitWidth: 900
        implicitHeight: 880
        color: root.col("surface_container", "#271d1d")

        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: if (root.countdown === 0) Qt.quit()
            Keys.onPressed: event => { if (event.key === Qt.Key_I) { root.identify(); event.accepted = true; } }

            // ---- Banner ----
            Item {
                id: banner
                width: parent.width
                height: 132
                clip: true
                Image {
                    width: parent.width
                    height: width * 414 / 735
                    y: -height * 0.2
                    source: "file://" + root.here + "/assets/himeko-banner.jpg"
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 1000
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
                    anchors { left: parent.left; bottom: parent.bottom; leftMargin: 28; bottomMargin: 6 }
                    Text {
                        text: "ASTRAL EXPRESS · BRIDGE CONTROL"
                        font.family: root.fontMain; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 1.6
                        color: root.col("primary", "#ffb3b0")
                    }
                    Text {
                        text: "Display Settings"
                        font.family: root.fontMain; font.pixelSize: 26; font.weight: Font.DemiBold
                        color: root.col("on_surface", "#f0dedd")
                    }
                    Text {
                        text: root.mons.length + " display" + (root.mons.length === 1 ? "" : "s") + " connected"
                        font.family: root.fontMain; font.pixelSize: 13
                        color: root.col("on_surface_variant", "#d7c1c0")
                    }
                }
            }

            Rectangle {
                id: chibi
                width: 104; height: 104; radius: 52
                x: parent.width - width - 30
                y: banner.height - height + 26
                z: 2
                color: root.col("surface_container", "#271d1d")
                ClippingRectangle {
                    anchors.fill: parent; anchors.margins: 4
                    radius: width / 2
                    border.width: 2; border.color: root.col("primary", "#ffb3b0")
                    Image {
                        anchors.fill: parent
                        source: "file://" + root.here + "/assets/himeko-chibi.jpg"
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 256
                        asynchronous: true
                    }
                }
            }

            Column {
                id: body
                anchors { top: banner.bottom; topMargin: 14; left: parent.left; right: parent.right; leftMargin: 28; rightMargin: 28 }
                spacing: 14

                // Himeko comment
                Rectangle {
                    width: parent.width - 120
                    height: 40; radius: 20
                    color: root.col("surface_container_high", "#322827")
                    Row {
                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                        spacing: 10
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "coffee"; font.family: root.fontIcon; font.pixelSize: 20
                            color: root.col("primary", "#ffb3b0")
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "<b>Himeko</b>  “" + root.himekoLine + "”"
                            textFormat: Text.StyledText
                            font.family: root.fontMain; font.pixelSize: 13
                            color: root.col("on_surface_variant", "#d7c1c0")
                        }
                    }
                }

                // ---- Arrangement canvas ----
                Rectangle {
                    id: canvas
                    width: parent.width
                    height: 250
                    radius: 23
                    color: root.col("surface_container_low", "#231919")
                    border.width: 1
                    border.color: root.col("outline_variant", "#524342")
                    clip: true

                    readonly property real pad: 34
                    readonly property var box: {
                        const list = root.mons;
                        if (!list.length) return { x: 0, y: 0, w: 1, h: 1 };
                        const x0 = Math.min(...list.map(m => m.x)), y0 = Math.min(...list.map(m => m.y));
                        const x1 = Math.max(...list.map(m => m.x + root.lw(m))), y1 = Math.max(...list.map(m => m.y + root.lh(m)));
                        return { x: x0, y: y0, w: Math.max(1, x1 - x0), h: Math.max(1, y1 - y0) };
                    }
                    readonly property real f: Math.min((width - 2 * pad) / box.w, (height - 2 * pad - 18) / box.h, 0.14)
                    readonly property real ox: (width - box.w * f) / 2 - box.x * f
                    readonly property real oy: (height - 18 - box.h * f) / 2 - box.y * f

                    Text {
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 10 }
                        text: "Drag displays to match your desk  ·  click one to edit it"
                        font.family: root.fontMain; font.pixelSize: 12
                        color: root.col("on_surface_variant", "#d7c1c0")
                        opacity: 0.75
                    }

                    Repeater {
                        model: root.mons
                        delegate: Rectangle {
                            id: mon
                            required property var modelData
                            required property int index
                            readonly property bool selected: index === root.sel
                            property bool moved: false
                            x: canvas.ox + modelData.x * canvas.f
                            y: canvas.oy + modelData.y * canvas.f
                            width: Math.max(40, root.lw(modelData) * canvas.f)
                            height: Math.max(28, root.lh(modelData) * canvas.f)
                            z: selected ? 2 : 1
                            radius: 12
                            opacity: modelData.enabled ? 1 : 0.45
                            color: !modelData.enabled ? "transparent"
                                 : selected ? root.col("primary_container", "#733333")
                                 : root.col("surface_container_highest", "#3d3232")
                            border.width: selected ? 2 : 1
                            border.color: selected ? root.col("primary", "#ffb3b0") : root.col("outline", "#a08c8b")

                            Rectangle {
                                x: 10; y: 10; width: 26; height: 26; radius: 13
                                color: mon.selected ? root.col("primary", "#ffb3b0") : root.col("surface_container", "#271d1d")
                                Text {
                                    anchors.centerIn: parent
                                    text: root.numberOf(mon.index)
                                    font.family: root.fontMain; font.pixelSize: 13; font.weight: Font.Bold
                                    color: mon.selected ? root.col("on_primary", "#571d1e") : root.col("on_surface", "#f0dedd")
                                }
                            }
                            Text {
                                visible: mon.modelData.name === root.primary
                                anchors { right: parent.right; top: parent.top; margins: 9 }
                                text: "star"
                                renderType: Text.NativeRendering
                                font.family: root.fontIcon
                                font.hintingPreference: Font.PreferNoHinting
                                font.weight: Font.DemiBold
                                font.variableAxes: ({ "FILL": 1, "opsz": 20 })
                                font.pixelSize: 20
                                color: root.col("primary", "#ffb3b0")
                            }
                            Column {
                                anchors.centerIn: parent
                                spacing: 2
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: mon.modelData.internal ? "laptop" : "desktop_windows"
                                    font.family: root.fontIcon; font.pixelSize: 26
                                    color: mon.selected ? root.col("on_primary_container", "#ffdad8") : root.col("on_surface_variant", "#d7c1c0")
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: mon.modelData.internal ? "Built-in display" : mon.modelData.model
                                    font.family: root.fontMain; font.pixelSize: 13; font.weight: Font.DemiBold
                                    color: mon.selected ? root.col("on_primary_container", "#ffdad8") : root.col("on_surface", "#f0dedd")
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: mon.modelData.enabled ? (mon.modelData.w + "×" + mon.modelData.h + " · " + Math.round(mon.modelData.r) + " Hz") : "Off"
                                    font.family: root.fontMain; font.pixelSize: 11
                                    color: mon.selected ? root.col("on_primary_container", "#ffdad8") : root.col("on_surface_variant", "#d7c1c0")
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: mon.modelData.enabled ? Qt.OpenHandCursor : Qt.PointingHandCursor
                                drag.target: mon.modelData.enabled ? mon : null
                                drag.threshold: 4
                                onPressed: root.sel = mon.index
                                onPositionChanged: if (drag.active) mon.moved = true
                                onReleased: {
                                    if (!mon.moved) return;
                                    root.place(mon.index, (mon.x - canvas.ox) / canvas.f, (mon.y - canvas.oy) / canvas.f);
                                }
                            }
                        }
                    }
                }

                // ---- Selected display header ----
                Item {
                    width: parent.width
                    height: 40
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Repeater {
                            model: root.order   // monitor indices in display-number order
                            delegate: Rectangle {
                                id: tab
                                required property int modelData
                                readonly property int index: modelData
                                readonly property var mon: root.mons[modelData]
                                readonly property bool active: index === root.sel
                                width: tabRow.implicitWidth + 26; height: 36
                                radius: active ? 12 : 18
                                color: active ? root.col("secondary_container", "#5d3f3e")
                                     : tabHover.hovered ? root.col("surface_container_highest", "#3d3232") : root.col("surface_container_high", "#322827")
                                Behavior on radius { NumberAnimation { duration: 140 } }
                                Row {
                                    id: tabRow
                                    anchors.centerIn: parent
                                    spacing: 8
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.numberOf(tab.index)
                                        font.family: root.fontMain; font.pixelSize: 13; font.weight: Font.Bold
                                        color: root.col("primary", "#ffb3b0")
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: (tab.mon.internal ? "Built-in display" : tab.mon.model) + (tab.mon.name === root.primary ? "  ★" : "")
                                        font.family: root.fontMain; font.pixelSize: 13; font.weight: Font.Medium
                                        color: tab.active ? root.col("on_secondary_container", "#ffdad8") : root.col("on_surface", "#f0dedd")
                                    }
                                }
                                HoverHandler { id: tabHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.sel = tab.index }
                            }
                        }
                    }
                    // Primary + enabled switch
                    Row {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        spacing: 10
                        Rectangle {
                            id: primaryBtn
                            readonly property bool isPrimary: root.cur !== null && root.cur.name === root.primary
                            anchors.verticalCenter: parent.verticalCenter
                            width: primaryRow.implicitWidth + 26; height: 36
                            radius: isPrimary ? 12 : 18
                            opacity: root.cur && root.cur.enabled ? 1 : 0.4
                            color: isPrimary ? root.col("primary_container", "#733333")
                                 : primaryHover.hovered ? root.col("surface_container_highest", "#3d3232") : "transparent"
                            border.width: isPrimary ? 0 : 1
                            border.color: root.col("outline", "#a08c8b")
                            Row {
                                id: primaryRow
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "star"
                                    renderType: Text.NativeRendering
                                    font.family: root.fontIcon
                                    font.hintingPreference: Font.PreferNoHinting
                                    font.variableAxes: ({ "FILL": primaryBtn.isPrimary ? 1 : 0, "opsz": 18 })
                                    font.pixelSize: 18
                                    color: root.col("primary", "#ffb3b0")
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: primaryBtn.isPrimary ? "Primary display" : "Make primary"
                                    font.family: root.fontMain; font.pixelSize: 13; font.weight: Font.Medium
                                    color: primaryBtn.isPrimary ? root.col("on_primary_container", "#ffdad8") : root.col("on_surface", "#f0dedd")
                                }
                            }
                            HoverHandler { id: primaryHover; cursorShape: primaryBtn.isPrimary ? Qt.ArrowCursor : Qt.PointingHandCursor }
                            TapHandler { onTapped: root.makePrimary() }
                        }
                        Item { width: 4; height: 1 }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.cur && root.cur.enabled ? "On" : "Off"
                            font.family: root.fontMain; font.pixelSize: 13
                            color: root.col("on_surface_variant", "#d7c1c0")
                        }
                        Rectangle {
                            id: sw
                            readonly property bool on: root.cur ? root.cur.enabled : false
                            width: 52; height: 32; radius: 16
                            color: on ? root.col("primary", "#ffb3b0") : root.col("surface_container_highest", "#3d3232")
                            border.width: on ? 0 : 2
                            border.color: root.col("outline", "#a08c8b")
                            Behavior on color { ColorAnimation { duration: 140 } }
                            Rectangle {
                                width: sw.on ? 24 : 16; height: width; radius: width / 2
                                anchors.verticalCenter: parent.verticalCenter
                                x: sw.on ? parent.width - width - 4 : 8
                                color: sw.on ? root.col("on_primary", "#571d1e") : root.col("outline", "#a08c8b")
                                Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                Behavior on width { NumberAnimation { duration: 160 } }
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.toggleEnabled() }
                        }
                    }
                }

                // ---- Settings for the selected display ----
                Rectangle {
                    width: parent.width
                    height: 300
                    radius: 23
                    color: root.col("surface_container_low", "#231919")
                    opacity: root.cur && root.cur.enabled ? 1 : 0.5
                    enabled: !!(root.cur && root.cur.enabled)

                    Flickable {
                        anchors.fill: parent
                        anchors.margins: 6
                        clip: true
                        contentHeight: groupsCol.implicitHeight + 12
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: groupsCol
                            width: parent.width
                            Repeater {
                                model: {
                                    const m = root.cur;
                                    if (!m) return [];
                                    const res = [];
                                    const seen = {};
                                    for (const md of m.modes) {
                                        const k = md.w + "x" + md.h;
                                        if (!seen[k]) { seen[k] = true; res.push(md); }
                                    }
                                    res.sort((a, b) => b.w * b.h - a.w * a.h);
                                    const rates = [...new Set(m.modes.filter(md => md.w === m.w && md.h === m.h).map(md => md.r))].sort((a, b) => b - a);
                                    return [
                                        { key: "res", title: "Resolution", icon: "aspect_ratio",
                                          options: res.map(md => ({ label: md.w + " × " + md.h, value: md.w + "x" + md.h, selected: md.w === m.w && md.h === m.h })) },
                                        { key: "rate", title: "Refresh rate", icon: "speed",
                                          options: rates.map(r => ({ label: (Number.isInteger(r) ? r : r.toFixed(2)) + " Hz", value: r, selected: Math.abs(r - m.r) < 0.01 })) },
                                        { key: "scale", title: "Scale", icon: "zoom_in",
                                          options: [1, 1.25, 1.5, 2].map(s => ({ label: Math.round(s * 100) + "%", value: s, selected: Math.abs(s - m.scale) < 0.001 })) },
                                        { key: "rot", title: "Orientation", icon: "screen_rotation",
                                          options: [["Landscape", 0], ["Portrait", 1], ["Landscape (flipped)", 2], ["Portrait (flipped)", 3]]
                                              .map(o => ({ label: o[0], value: o[1], selected: m.transform === o[1] })) }
                                    ];
                                }
                                delegate: Item {
                                    id: group
                                    required property var modelData
                                    required property int index
                                    width: groupsCol.width
                                    height: Math.max(52, chips.implicitHeight + 22)
                                    Rectangle {
                                        visible: group.index > 0
                                        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 14; rightMargin: 14 }
                                        height: 1
                                        color: root.col("outline_variant", "#524342")
                                        opacity: 0.6
                                    }
                                    Row {
                                        x: 14; y: 16
                                        width: 190
                                        spacing: 10
                                        Text {
                                            text: group.modelData.icon; font.family: root.fontIcon; font.pixelSize: 20
                                            color: root.col("primary", "#ffb3b0")
                                        }
                                        Text {
                                            text: group.modelData.title
                                            font.family: root.fontMain; font.pixelSize: 15; font.weight: Font.Medium
                                            color: root.col("on_surface", "#f0dedd")
                                        }
                                    }
                                    Flow {
                                        id: chips
                                        x: 200; y: 11
                                        width: group.width - 214
                                        spacing: 8
                                        Repeater {
                                            model: group.modelData.options
                                            delegate: Rectangle {
                                                id: chip
                                                required property var modelData
                                                width: chipText.implicitWidth + 28; height: 32
                                                radius: modelData.selected ? 10 : 16
                                                color: modelData.selected ? root.col("primary_container", "#733333")
                                                     : chipHover.hovered ? root.col("surface_container_highest", "#3d3232")
                                                     : root.col("surface_container_high", "#322827")
                                                border.width: modelData.selected ? 0 : 1
                                                border.color: root.col("outline_variant", "#524342")
                                                Behavior on radius { NumberAnimation { duration: 140 } }
                                                Text {
                                                    id: chipText
                                                    anchors.centerIn: parent
                                                    text: chip.modelData.label
                                                    font.family: root.fontMain; font.pixelSize: 13
                                                    font.weight: chip.modelData.selected ? Font.DemiBold : Font.Normal
                                                    color: chip.modelData.selected ? root.col("on_primary_container", "#ffdad8") : root.col("on_surface", "#f0dedd")
                                                }
                                                HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                                                TapHandler { onTapped: root.pick(group.modelData.key, chip.modelData.value) }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---- Footer ----
            Item {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 28; bottomMargin: 22 }
                height: 40

                Rectangle {
                    id: identifyBtn
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    width: identifyRow.implicitWidth + 28; height: 40; radius: 20
                    color: identifyHover.hovered ? root.col("secondary_container", "#5d3f3e") : root.col("surface_container_high", "#322827")
                    Row {
                        id: identifyRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "pin"; font.family: root.fontIcon; font.pixelSize: 18
                            color: root.col("primary", "#ffb3b0")
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Identify"
                            font.family: root.fontMain; font.pixelSize: 14; font.weight: Font.Medium
                            color: root.col("on_surface", "#f0dedd")
                        }
                    }
                    HoverHandler { id: identifyHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.identify() }
                }

                Rectangle {
                    anchors { left: identifyBtn.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    width: advRow.implicitWidth + 24; height: 36; radius: 18
                    color: advHover.hovered ? root.col("surface_container_highest", "#3d3232") : "transparent"
                    Row {
                        id: advRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "tune"; font.family: root.fontIcon; font.pixelSize: 18
                            color: root.col("primary", "#ffb3b0")
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Advanced (nwg-displays)…"
                            font.family: root.fontMain; font.pixelSize: 13
                            color: root.col("on_surface_variant", "#d7c1c0")
                        }
                    }
                    HoverHandler { id: advHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { Quickshell.execDetached([root.nwgDisplays]); Qt.quit(); } }
                }

                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 10
                    Rectangle {
                        width: cancelText.implicitWidth + 40; height: 40; radius: 20
                        color: cancelHover.hovered ? root.col("surface_container_highest", "#3d3232") : root.col("surface_container_high", "#322827")
                        Text {
                            id: cancelText
                            anchors.centerIn: parent
                            text: root.dirty ? "Reset" : "Close"
                            font.family: root.fontMain; font.pixelSize: 14; font.weight: Font.Medium
                            color: root.col("on_surface", "#f0dedd")
                        }
                        HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { if (!root.dirty) { Qt.quit(); return; } root.mons = JSON.parse(JSON.stringify(root.original)); root.primary = root.originalPrimary; } }
                    }
                    Rectangle {
                        width: applyText.implicitWidth + 48; height: 40; radius: 20
                        opacity: root.dirty && !root.busy ? 1 : 0.4
                        color: root.col("primary", "#ffb3b0")
                        Text {
                            id: applyText
                            anchors.centerIn: parent
                            text: root.busy ? "Applying…" : "Apply"
                            font.family: root.fontMain; font.pixelSize: 14; font.weight: Font.DemiBold
                            color: root.col("on_primary", "#571d1e")
                        }
                        HoverHandler { cursorShape: root.dirty ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        TapHandler { onTapped: root.apply() }
                    }
                }
            }

            // ---- "Keep these settings?" prompt with auto-revert ----
            Rectangle {
                anchors.fill: parent
                visible: root.countdown > 0
                color: Qt.alpha(root.col("scrim", "#000000"), 0.55)
                z: 10
                MouseArea { anchors.fill: parent }
                Rectangle {
                    anchors.centerIn: parent
                    width: 440; height: 210; radius: 28
                    color: root.col("surface_container_high", "#322827")
                    border.width: 1; border.color: root.col("outline_variant", "#524342")
                    Column {
                        anchors { fill: parent; margins: 26 }
                        spacing: 10
                        Text {
                            text: "Keep these display settings?"
                            font.family: root.fontMain; font.pixelSize: 20; font.weight: Font.DemiBold
                            color: root.col("on_surface", "#f0dedd")
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "Reverting to the previous settings in " + root.countdown + " s."
                            font.family: root.fontMain; font.pixelSize: 14
                            color: root.col("on_surface_variant", "#d7c1c0")
                        }
                    }
                    Row {
                        anchors { right: parent.right; bottom: parent.bottom; margins: 22 }
                        spacing: 10
                        Rectangle {
                            width: revertText.implicitWidth + 40; height: 40; radius: 20
                            color: revertHover.hovered ? root.col("surface_container_highest", "#3d3232") : "transparent"
                            border.width: 1; border.color: root.col("outline", "#a08c8b")
                            Text {
                                id: revertText
                                anchors.centerIn: parent
                                text: "Revert"
                                font.family: root.fontMain; font.pixelSize: 14; font.weight: Font.Medium
                                color: root.col("primary", "#ffb3b0")
                            }
                            HoverHandler { id: revertHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.revert() }
                        }
                        Rectangle {
                            width: keepText.implicitWidth + 44; height: 40; radius: 20
                            color: root.col("primary", "#ffb3b0")
                            Text {
                                id: keepText
                                anchors.centerIn: parent
                                text: "Keep changes"
                                font.family: root.fontMain; font.pixelSize: 14; font.weight: Font.DemiBold
                                color: root.col("on_primary", "#571d1e")
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.keep() }
                        }
                    }
                }
            }
        }
    }
}
