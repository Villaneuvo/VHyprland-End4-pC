// Logic self-check. Run: qs -p ~/.config/hypr/custom/himeko-files/selftest.qml
// Prints "ok   name" or "FAIL name: got …, want …", then "selftest: N failures".
import QtQuick
import Quickshell

ShellRoot {
    id: t
    property int failures: 0
    function check(name, got, want) {
        const ok = JSON.stringify(got) === JSON.stringify(want);
        console.log((ok ? "ok   " : "FAIL ") + name + (ok ? "" : ": got " + JSON.stringify(got) + ", want " + JSON.stringify(want)));
        if (!ok) failures++;
    }
    // quit from a timer: Qt.quit() during startup, before the event loop runs, is ignored
    Timer { id: done; interval: 50; onTriggered: Qt.quit() }
    Component.onCompleted: { try { run(); } catch (e) { failures++; console.log("FAIL exception: " + e); } finally { console.log("selftest: " + failures + " failures"); done.start(); } }
    function run() {
        // ---- dates (Fs.date) ----
        const now = new Date(2026, 9, 16, 12, 0, 0);
        const at = (y, mo, d, h, mi) => new Date(y, mo - 1, d, h, mi);
        check("date: seconds ago", Fs.date(new Date(now.getTime() - 30000), now), "Just now");
        check("date: minutes ago", Fs.date(new Date(now.getTime() - 5 * 60000), now), "5 min ago");
        check("date: 59 minutes ago", Fs.date(new Date(now.getTime() - 59 * 60000), now), "59 min ago");
        check("date: earlier today", Fs.date(at(2026, 10, 16, 8, 5), now), "Today, 08:05");
        check("date: yesterday", Fs.date(at(2026, 10, 15, 16, 28), now), "Yesterday, 16:28");
        check("date: 3 days ago", Fs.date(at(2026, 10, 13, 10, 0), now), "3 days ago");
        check("date: 6 days ago", Fs.date(at(2026, 10, 10, 23, 59), now), "6 days ago");
        check("date: this year", Fs.date(at(2026, 10, 9, 10, 0), now), "9 Oct");
        check("date: last year", Fs.date(at(2025, 12, 31, 10, 0), now), "31 Dec 2025");
        check("date: future", Fs.date(at(2026, 10, 17, 9, 0), now), "17 Oct");

        // ---- item counts (Fs.tallyCounts, Fs.countLabel) ----
        check("tally: counts per parent", Fs.tallyCounts("/a/x\n/a/x\n/a/y\n"), { "/a/x": 2, "/a/y": 1 });
        check("tally: empty output", Fs.tallyCounts(""), {});
        check("tally: names with spaces", Fs.tallyCounts("/a/My Folder\n"), { "/a/My Folder": 1 });
        check("label: unknown", Fs.countLabel(undefined), "Folder");
        check("label: empty", Fs.countLabel(0), "Empty");
        check("label: one", Fs.countLabel(1), "1 item");
        check("label: many", Fs.countLabel(24), "24 items");
        // unreadable subfolders (find prints "Permission denied") are unknown, not empty
        const denied = "find: '/a/root': Permission denied\nfind: '/a/it\\'s': Permission denied\nfind: '/a/loop': File system loop detected\n";
        check("tally: unreadable is unknown", Fs.tallyCounts("/a/x\n", denied), { "/a/x": 1, "/a/root": null, "/a/it's": null });
        const c = Fs.tallyCounts("/a/x\n", denied);
        check("countOf: listed", Fs.countOf(c, "/a/x"), 1);
        check("countOf: unlisted is empty", Fs.countOf(c, "/a/y"), 0);
        check("countOf: unreadable", Fs.countLabel(Fs.countOf(c, "/a/root")), "Folder");
        check("countOf: not counted yet", Fs.countLabel(Fs.countOf(null, "/a/x")), "Folder");

        // ---- thumbnails (Fs.canThumb) ----
        Fs.thumbExts = { "pdf": true, "mp3": true, "ts": true };
        Fs.thumbFailed = { "/x/bad.pdf": true };
        check("canThumb: image", Fs.canThumb({ isDir: false, suffix: "PNG", path: "/x/a.PNG" }), true);
        check("canThumb: pdf", Fs.canThumb({ isDir: false, suffix: "pdf", path: "/x/a.pdf" }), true);
        check("canThumb: code never", Fs.canThumb({ isDir: false, suffix: "ts", path: "/x/a.ts" }), false);
        check("canThumb: failed", Fs.canThumb({ isDir: false, suffix: "pdf", path: "/x/bad.pdf" }), false);
        check("canThumb: no thumbnailer", Fs.canThumb({ isDir: false, suffix: "zip", path: "/x/a.zip" }), false);
        check("canThumb: folder", Fs.canThumb({ isDir: true, suffix: "", path: "/x/d" }), false);
        check("kinds: new video", Fs.kindOf({ isDir: false, suffix: "ogv" }), "video");
        check("kinds: ttc font", Fs.kindOf({ isDir: false, suffix: "ttc" }), "font");
        check("kinds: comic", Fs.kindOf({ isDir: false, suffix: "cbz" }), "doc");
        Fs.thumbExts = {}; Fs.thumbFailed = {};

        // ---- Quick Look rules ----
        check("type: image", Fs.previewType("image", ""), "image");
        check("type: code", Fs.previewType("code", ""), "text");
        check("type: pdf", Fs.previewType("pdf", ""), "pdf");
        check("type: font", Fs.previewType("font", ""), "font");
        check("type: folder", Fs.previewType("folder", ""), "folder");
        check("type: doc waits for mime", Fs.previewType("doc", ""), "");
        check("type: txt", Fs.previewType("doc", "text/plain"), "text");
        check("type: odt", Fs.previewType("doc", "application/vnd.oasis.opendocument.text"), "info");
        check("type: djvu", Fs.previewType("doc", "image/vnd.djvu"), "info");
        check("type: json", Fs.previewType("file", "application/json"), "text");
        check("type: odd audio", Fs.previewType("file", "audio/x-mod"), "audio");
        check("type: zip", Fs.previewType("archive", "application/zip"), "info");
        check("step: next", Fs.stepIndex(2, 1, 5), 3);
        check("step: stops at end", Fs.stepIndex(4, 1, 5), 4);
        check("step: stops at start", Fs.stepIndex(0, -1, 5), 0);
        check("step: missing item", Fs.stepIndex(-1, 1, 5), 0);

        // ---- PDF wheel: a page per notch (120), touchpads add up small deltas ----
        check("wheel: one notch down", Fs.wheelStep(0, -120), { flip: 1, acc: 0 });
        check("wheel: small delta waits", Fs.wheelStep(0, -15), { flip: 0, acc: -15 });
        check("wheel: deltas add up", Fs.wheelStep(-105, -15), { flip: 1, acc: 0 });
        check("wheel: two notches up", Fs.wheelStep(0, 240), { flip: -2, acc: 0 });
        check("wheel: back and forth", Fs.wheelStep(-60, 60), { flip: 0, acc: 0 });
        // ---- properties rules ----
        check("access: file rw", Fs.accessOf(0o644, "u", false), "Read and Write");
        check("access: file r", Fs.accessOf(0o644, "g", false), "Read-Only");
        check("access: file none", Fs.accessOf(0o600, "o", false), "None");
        check("access: dir rwx", Fs.accessOf(0o755, "u", true), "Create and Delete Files");
        check("access: dir r-x", Fs.accessOf(0o755, "g", true), "Access Files");
        check("access: dir r--", Fs.accessOf(0o744, "g", true), "List Files Only");
        check("access: dir custom", Fs.accessOf(0o730, "g", true), "");
        check("withAccess: file others none", Fs.withAccess(0o644, "o", "None", false), 0o640);
        check("withAccess: keeps setuid", Fs.withAccess(0o4755, "g", "List Files Only", true), 0o4745);
        check("withAccess: file keeps x", Fs.withAccess(0o755, "u", "Read-Only", false), 0o555);
        check("exec: off", Fs.isExec(0o644), false);
        check("exec: on where readable", Fs.withExec(0o640, true), 0o750);
        check("exec: clear", Fs.withExec(0o755, false), 0o644);
        check("shared: same", Fs.shared(["a", "a"]), "a");
        check("shared: mixed", Fs.shared(["a", "b"]), "Mixed");
        check("sizeText", Fs.sizeText(2412345), "2.3 MB (2,412,345 bytes)");
        check("sizeText small", Fs.sizeText(512), "512 bytes");
        check("fullDate", Fs.fullDate(new Date(2026, 9, 18, 16, 30)), "Sunday, 18 October 2026, 16:30");
        // ---- properties redesign rules ----
        check("levels: owner has no None", Fs.levelsFor("u", false), ["Read-Only", "Read and Write"]);
        check("levels: others", Fs.levelsFor("o", true), ["None", "List Files Only", "Access Files", "Create and Delete Files"]);
        check("umask 002", Fs.umaskLevels(0o002), { files: { u: "Read and Write", g: "Read and Write", o: "Read-Only" },
              folders: { u: "Create and Delete Files", g: "Create and Delete Files", o: "Access Files" } });
        check("umask 022", Fs.umaskLevels(0o022), { files: { u: "Read and Write", g: "Read-Only", o: "Read-Only" },
              folders: { u: "Create and Delete Files", g: "Access Files", o: "Access Files" } });
        check("symbolic: file read-only", Fs.symbolic("g", "Read-Only", false), "g+r,g-w");
        check("symbolic: file rw", Fs.symbolic("g", "Read and Write", false), "g+rw");
        check("symbolic: file none", Fs.symbolic("o", "None", false), "o-rw");
        check("symbolic: dir none", Fs.symbolic("o", "None", true), "o-rwx");
        check("symbolic: dir list", Fs.symbolic("o", "List Files Only", true), "o+r,o-wx");
        check("symbolic: dir access", Fs.symbolic("u", "Access Files", true), "u+rx,u-w");
        check("symbolic: dir all", Fs.symbolic("g", "Create and Delete Files", true), "g+rwx");
        check("symbolicAll", Fs.symbolicAll({ u: "Read and Write", g: "Read-Only", o: "None" }, false), "u+rw,g+r,g-w,o-rw");
        // ---- motion tokens (Theme) ----
        check("curve: fastSpatial", Theme.curve.fastSpatial, [0.42, 1.67, 0.21, 0.90, 1, 1]);
        check("curve: enter", Theme.curve.enter, [0.05, 0.7, 0.1, 1, 1, 1]);
        const was = Theme.animate;
        Theme.animate = true;
        check("dur: effects", Theme.dur("effects"), 200);
        check("dur: spatial", Theme.dur("spatial"), 500);
        Theme.animate = false;
        check("dur: off", Theme.dur("fastSpatial"), 0);
        Theme.animate = was;
    }
}
