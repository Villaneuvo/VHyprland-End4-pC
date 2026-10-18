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
